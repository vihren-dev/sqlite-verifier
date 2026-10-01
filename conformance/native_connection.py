"""Persistent C-API connections to the explicitly pinned SQLite shared library."""

import ctypes as c
from pathlib import Path
import shutil
import struct
import sys
import time
from typing import TypeAlias
from dataclasses import dataclass
from contextlib import nullcontext

from conformance.native_library import SOURCE_ID, load_library

Cell: TypeAlias = tuple[int, int | bytes | None]
Row: TypeAlias = tuple[Cell, ...]
# SQL semantic errors; environmental/connection failures must never become model evidence.
SQL_ERRORS = (1, 18, 19, 20)  # ERROR, TOOBIG, CONSTRAINT, MISMATCH


def encoded_sql(sql: str) -> bytes:
    """Refuse NUL-truncated SQL at every C API boundary; bound values retain arbitrary bytes."""
    if "\x00" in sql:
        raise ValueError("SQL source contains NUL")
    return sql.encode()


@dataclass(frozen=True)
class NativeResult:
    """Column names are available even when stepping returns no rows."""

    columns: tuple[str, ...]
    rows: list[Row]


class NativeError(RuntimeError):
    """Retain extended result codes without treating diagnostic text as an oracle."""

    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


def library_path(executable_name: str = "sqlite3") -> Path:
    """Resolve the library beside the Nix shell's SQLite, never the system loader default."""
    executable = shutil.which(executable_name)
    if executable is None:
        raise RuntimeError("Enter the pinned Nix development shell: sqlite3 is missing")
    suffix = "dylib" if sys.platform == "darwin" else "so"
    path = Path(executable).resolve().parent.parent / "lib" / f"libsqlite3.{suffix}"
    return path.resolve(strict=True)




class Connection:
    """One explicit autocommit connection with bounded statements and byte-exact reads."""

    def __init__(self, library: c.CDLL, path: Path, *, vfs: bytes | None = None) -> None:
        self.library = library
        self.handle = c.c_void_p()
        self.deadline = time.monotonic() + 5
        self.progress = c.CFUNCTYPE(c.c_int, c.c_void_p)(lambda _: int(time.monotonic() > self.deadline))
        opened = library.sqlite3_open_v2(str(path).encode(), c.byref(self.handle), 6, vfs)
        if opened:
            message = library.sqlite3_errmsg(self.handle).decode(errors="replace")
            library.sqlite3_close(self.handle)
            raise NativeError(opened, message)
        library.sqlite3_busy_timeout(self.handle, 100)
        library.sqlite3_limit(self.handle, 2, 2000)
        library.sqlite3_progress_handler(self.handle, 1000, self.progress, None)
        try:
            self.configure(1010, 0)  # DEFENSIVE: preserve the reviewed native profile.
            for option in (1013, 1014):  # Verify library-default DQS_DML and DQS_DDL.
                if self.configure(option, -1) != 1:
                    raise RuntimeError("SQLite connection configuration readback failed")
            if library.sqlite3_limit(self.handle, 2, -1) != 2000:
                raise RuntimeError("SQLite connection does not match the execution profile")
            self.execute_script("PRAGMA trusted_schema=ON; PRAGMA writable_schema=OFF;")
        except Exception:
            self.close()
            raise

    def configure(self, option: int, value: int) -> int:
        """Set or query a boolean sqlite3_db_config option, checking the native result."""
        actual = c.c_int()
        self.check(self.library.sqlite3_db_config(self.handle, option, c.c_int(value), c.byref(actual)))
        return actual.value

    def check(self, code: int) -> None:
        """Capture the error before another operation can overwrite the connection state."""
        if code not in (0, 100, 101):
            raise NativeError(self.library.sqlite3_extended_errcode(self.handle),
                              self.library.sqlite3_errmsg(self.handle).decode(errors="replace"))

    def execute_script(self, sql: str) -> None:
        """Initialize fixtures/configuration; migrations use single-statement query instead."""
        self.deadline = time.monotonic() + 5
        self.check(self.library.sqlite3_exec(self.handle, encoded_sql(sql), None, None, None))

    def cell(self, statement: c.c_void_p, index: int) -> Cell:
        """Read storage class before extraction; TEXT and BLOB retain all bytes, including NUL."""
        kind = self.library.sqlite3_column_type(statement, index)
        if kind == 1:
            return kind, self.library.sqlite3_column_int64(statement, index)
        if kind == 2:
            value = self.library.sqlite3_column_double(statement, index)
            return kind, struct.unpack(">Q", struct.pack(">d", value))[0]
        if kind in (3, 4):
            read = self.library.sqlite3_column_text if kind == 3 else self.library.sqlite3_column_blob
            pointer = read(statement, index)
            size = self.library.sqlite3_column_bytes(statement, index)
            return kind, c.string_at(pointer, size) if size else b""
        return 5, None

    def bind(self, statement: c.c_void_p, index: int, cell: Cell) -> None:
        """Bind exact fixture storage, including infinities and SQLite's NaN-to-NULL conversion."""
        kind, value = cell
        if kind == 5 and value is None:
            code = self.library.sqlite3_bind_null(statement, index)
        elif kind == 1 and isinstance(value, int) and -(2**63) <= value < 2**63:
            code = self.library.sqlite3_bind_int64(statement, index, value)
        elif kind == 2 and isinstance(value, int) and 0 <= value < 2**64:
            number = struct.unpack(">d", struct.pack(">Q", value))[0]
            code = self.library.sqlite3_bind_double(statement, index, number)
        elif kind in (3, 4) and isinstance(value, bytes):
            function = self.library.sqlite3_bind_text if kind == 3 else self.library.sqlite3_bind_blob
            code = function(statement, index, value, len(value), c.c_void_p(-1))  # SQLITE_TRANSIENT
        else:
            raise ValueError("Invalid typed SQLite fixture cell")
        self.check(code)

    def query(self, sql: str, parameters: tuple[Cell, ...] = ()) -> list[Row]:
        """Keep the existing row-only observation API over the shape-aware executor."""
        return self.query_result(sql, parameters).rows

    def query_result(self, sql: str, parameters: tuple[Cell, ...] = (), *,
                     readonly: bool = False) -> NativeResult:
        """Restrict supplementary probes before preparation can itself change settings."""
        from conformance.native_probe import select_probe
        with select_probe(self) if readonly else nullcontext():
            return self._query_result(sql, parameters, readonly=readonly)

    def _query_result(self, sql: str, parameters: tuple[Cell, ...], *,
                      readonly: bool) -> NativeResult:
        """Require complete binding and finalize even after execution or validation failure."""
        self.deadline = time.monotonic() + 5
        statement, tail = c.c_void_p(), c.c_char_p()
        encoded = encoded_sql(sql)
        self.check(self.library.sqlite3_prepare_v2(self.handle, encoded, len(encoded),
                                                 c.byref(statement), c.byref(tail)))
        try:
            if not statement.value or (tail.value or b"").strip():
                raise ValueError("Expected one complete SQL statement")
            if self.library.sqlite3_bind_parameter_count(statement) != len(parameters):
                raise ValueError("Expected one typed value per SQLite parameter slot")
            if readonly and (not self.library.sqlite3_stmt_readonly(statement) or
                             self.library.sqlite3_stmt_isexplain(statement)):
                raise ValueError("Supplementary probe must be a read-only SELECT")
            columns = tuple(self.library.sqlite3_column_name(statement, index).decode()
                            for index in range(self.library.sqlite3_column_count(statement)))
            for index, cell in enumerate(parameters, 1):
                self.bind(statement, index, cell)
            rows: list[Row] = []
            while True:
                code = self.library.sqlite3_step(statement)
                self.check(code)
                if code == 101:
                    return NativeResult(columns, rows)
                rows.append(tuple(self.cell(statement, index)
                                  for index in range(self.library.sqlite3_column_count(statement))))
        finally:
            self.library.sqlite3_finalize(statement)

    @property
    def transaction_open(self) -> bool:
        """Use SQLite's autocommit bit, not a Python wrapper's transaction policy."""
        return not bool(self.library.sqlite3_get_autocommit(self.handle))

    def close(self) -> None:
        """Finalize the connection only after its last observation has been collected."""
        if self.handle.value:
            self.check(self.library.sqlite3_close(self.handle))
            self.handle = c.c_void_p()
