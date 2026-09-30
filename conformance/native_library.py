"""C signatures and source identity for the pinned SQLite evidence engine."""

import ctypes as c
from pathlib import Path

SOURCE_ID = "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b"


def load_library(path: Path, version: str = "3.51.0") -> c.CDLL:
    """Declare C argument widths once; pointer defaults would truncate addresses."""
    library = c.CDLL(str(path))
    signatures = {
        "open": ([c.c_char_p, c.POINTER(c.c_void_p)], c.c_int),
        "close": ([c.c_void_p], c.c_int),
        "libversion": ([], c.c_char_p), "sourceid": ([], c.c_char_p),
        "compileoption_used": ([c.c_char_p], c.c_int),
        "get_autocommit": ([c.c_void_p], c.c_int),
        "set_authorizer": ([c.c_void_p, c.c_void_p, c.c_void_p], c.c_int),
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
        "column_name": ([c.c_void_p, c.c_int], c.c_char_p),
        "bind_parameter_count": ([c.c_void_p], c.c_int),
        "stmt_readonly": ([c.c_void_p], c.c_int),
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
    source = {"3.51.0": SOURCE_ID, "3.46.0": "2024-05-23 13:25:27 96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e"}[version]
    if library.sqlite3_libversion().decode() != version or library.sqlite3_sourceid().decode() != source:
        raise RuntimeError("SQLite library version/source ID does not match the pin")
    if not library.sqlite3_compileoption_used(b"MAX_COLUMN=2000"):
        raise RuntimeError("SQLite compile options do not match the profile")
    return library

