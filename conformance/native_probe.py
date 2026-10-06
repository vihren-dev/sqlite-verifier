"""A native authorizer boundary for supplementary SELECT-only probes."""

from collections.abc import Iterator
from contextlib import contextmanager
import ctypes as c

from conformance.native_connection import Connection, NativeError


@contextmanager
def select_probe(connection: Connection) -> Iterator[None]:
    """Preserve acquisition authorization while rejecting effects during preparation."""
    previous = getattr(connection, "authorizer", None)
    denied = False

    def authorize(context: int, action: int, first: bytes | None, second: bytes | None,
                  database: bytes | None, trigger: bytes | None) -> int:
        """Only reads, SELECT, recursive queries and ordinary functions may prepare."""
        nonlocal denied
        # SQLite authorizer constants READ, SELECT, FUNCTION, RECURSIVE.
        if action not in {20, 21, 31, 33} or action == 31 and second in {
                b"load_extension", b"random", b"randomblob"}:
            denied = True
            return 1  # SQLITE_DENY: no stepping (or PRAGMA preparation effect).
        return previous(context, action, first, second, database, trigger) if previous else 0

    callback = c.CFUNCTYPE(c.c_int, c.c_void_p, c.c_int,
                          c.c_char_p, c.c_char_p, c.c_char_p, c.c_char_p)(authorize)
    connection.check(connection.library.sqlite3_set_authorizer(connection.handle, callback, None))
    try:
        yield
    except NativeError as error:
        if denied:
            raise ValueError("Supplementary probe must be a read-only SELECT") from error
        raise
    finally:
        connection.check(connection.library.sqlite3_set_authorizer(connection.handle, previous, None))
