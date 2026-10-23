"""A native authorizer boundary for supplementary SELECT-only probes."""

from collections.abc import Iterator
from contextlib import contextmanager
import ctypes as c

from conformance.native_connection import Connection, NativeError

READ_PRAGMAS = {b"table_info", b"foreign_key_list"}
"""The pragmas that a probe may prepare: they read the schema and change nothing."""


@contextmanager
def select_probe(connection: Connection) -> Iterator[None]:
    """Preserve acquisition authorization while rejecting effects during preparation."""
    previous = getattr(connection, "authorizer", None)
    denied = False

    def authorize(context: int, action: int, first: bytes | None, second: bytes | None,
                  database: bytes | None, trigger: bytes | None) -> int:
        """Only reads, SELECT, recursive queries, ordinary functions and the pragmas that read the
        schema may prepare. A table-valued `pragma_table_info` or `pragma_foreign_key_list` of
        the probed query prepares its pragma when the probe runs."""
        nonlocal denied
        # SQLite authorizer constants READ, SELECT, FUNCTION, RECURSIVE and PRAGMA.
        if action not in {20, 21, 31, 33} and not (action == 19 and first in READ_PRAGMAS) or action == 31 and second in {
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
