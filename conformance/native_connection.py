"""Persistent C-API connections to the explicitly pinned SQLite shared library."""

import ctypes as c
from pathlib import Path
import shutil
import struct
import sys
import time
from typing import TypeAlias

Cell: TypeAlias = tuple[int, int | bytes | None]
Row: TypeAlias = tuple[Cell, ...]
SOURCE_ID = "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b"


class NativeError(RuntimeError):
    """Retain extended result codes without treating diagnostic text as an oracle."""

    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


def library_path() -> Path:
    """Resolve the library beside the Nix shell's SQLite, never the system loader default."""
    executable = shutil.which("sqlite3")
    if executable is None:
        raise RuntimeError("Enter the pinned Nix development shell: sqlite3 is missing")
    suffix = "dylib" if sys.platform == "darwin" else "so"
    path = Path(executable).resolve().parent.parent / "lib" / f"libsqlite3.{suffix}"
    return path.resolve(strict=True)


def load_library(path: Path) -> c.CDLL:
    """Declare C argument widths once; pointer defaults would truncate addresses."""
    library = c.CDLL(str(path))
    signatures = {
        "open": ([c.c_char_p, c.POINTER(c.c_void_p)], c.c_int),
        "close": ([c.c_void_p], c.c_int),
        "libversion": ([], c.c_char_p), "sourceid": ([], c.c_char_p),
        "compileoption_used": ([c.c_char_p], c.c_int),
        "get_autocommit": ([c.c_void_p], c.c_int),
        "busy_timeout": ([c.c_void_p, c.c_int], c.c_int),
        "db_config": ([c.c_void_p, c.c_int], c.c_int),
        "limit": ([c.c_void_p, c.c_int, c.c_int], c.c_int),
        "extended_errcode": ([c.c_void_p], c.c_int),
        "errmsg": ([c.c_void_p], c.c_char_p),
        "exec": ([c.c_void_p, c.c_char_p, c.c_void_p, c.c_void_p, c.c_void_p], c.c_int),
        "prepare_v2": ([c.c_void_p, c.c_char_p, c.c_int, c.POINTER(c.c_void_p),
                        c.POINTER(c.c_char_p)], c.c_int),
        "bind_null": ([c.c_void_p, c.c_int], c.c_int),
        "bind_int64": ([c.c_void_p, c.c_int, c.c_int64], c.c_int),
        "bind_double": ([c.c_void_p, c.c_int, c.c_double], c.c_int),
        "bind_text": ([c.c_void_p, c.c_int, c.c_char_p, c.c_int, c.c_void_p], c.c_int),
        "bind_blob": ([c.c_void_p, c.c_int, c.c_char_p, c.c_int, c.c_void_p], c.c_int),
        "step": ([c.c_void_p], c.c_int), "finalize": ([c.c_void_p], c.c_int),
        "column_count": ([c.c_void_p], c.c_int),
        "column_type": ([c.c_void_p, c.c_int], c.c_int),
        "column_int64": ([c.c_void_p, c.c_int], c.c_int64),
        "column_double": ([c.c_void_p, c.c_int], c.c_double),
        "column_text": ([c.c_void_p, c.c_int], c.c_void_p),
        "column_blob": ([c.c_void_p, c.c_int], c.c_void_p),
        "column_bytes": ([c.c_void_p, c.c_int], c.c_int),
        "progress_handler": ([c.c_void_p, c.c_int, c.c_void_p, c.c_void_p], None),
    }
    for name, (arguments, result) in signatures.items():
        function = getattr(library, "sqlite3_" + name)
        function.argtypes, function.restype = arguments, result
    if library.sqlite3_libversion() != b"3.51.0" or library.sqlite3_sourceid().decode() != SOURCE_ID:
        raise RuntimeError("SQLite library version/source ID does not match the pin")
    if not library.sqlite3_compileoption_used(b"MAX_COLUMN=2000"):
        raise RuntimeError("SQLite compile options do not match the profile")
    return library


class Connection:
    """One explicit autocommit connection with bounded statements and byte-exact reads."""

    def __init__(self, library: c.CDLL, path: Path) -> None:
        self.library = library
        self.handle = c.c_void_p()
        self.deadline = time.monotonic() + 5
        self.progress = c.CFUNCTYPE(c.c_int, c.c_void_p)(lambda _: int(time.monotonic() > self.deadline))
        opened = library.sqlite3_open(str(path).encode(), c.byref(self.handle))
        if opened:
            message = library.sqlite3_errmsg(self.handle).decode(errors="replace")
            library.sqlite3_close(self.handle)
            raise NativeError(opened, message)
        library.sqlite3_busy_timeout(self.handle, 100)
        library.sqlite3_limit(self.handle, 2, 2000)
        library.sqlite3_progress_handler(self.handle, 1000, self.progress, None)
        try:
            # Match the shell profile without changing the shared engine build.
            for option in (1010, 1013, 1014):  # DEFENSIVE, DQS_DML, DQS_DDL
                self.configure(option, 0)
                if self.configure(option, -1) != 0:
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
        self.check(self.library.sqlite3_exec(self.handle, sql.encode(), None, None, None))

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
        """Prepare exactly one statement and finalize it even after an execution failure."""
        self.deadline = time.monotonic() + 5
        statement, tail = c.c_void_p(), c.c_char_p()
        encoded = sql.encode()
        self.check(self.library.sqlite3_prepare_v2(self.handle, encoded, len(encoded),
                                                 c.byref(statement), c.byref(tail)))
        try:
            if not statement.value or (tail.value or b"").strip():
                raise ValueError("Expected one complete SQL statement")
            for index, cell in enumerate(parameters, 1):
                self.bind(statement, index, cell)
            rows: list[Row] = []
            while True:
                code = self.library.sqlite3_step(statement)
                self.check(code)
                if code == 101:
                    return rows
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
