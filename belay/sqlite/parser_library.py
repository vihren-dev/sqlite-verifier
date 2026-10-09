"""Load the SQLite parser library into this process and call its C API through `ctypes`.

The library holds one parser for each grammar identity (see `parser/library.h`). The
caller gives the library's path; the binding never searches the environment's library
path. It loads each path once per process, reads the metadata once, and refuses a
library with another API version. The library makes no promise for concurrent calls,
and `ctypes` releases Python's global interpreter lock during a foreign call, so the
binding holds its own lock for each call.
"""

from collections.abc import Callable
import ctypes
import json
from pathlib import Path
from threading import Lock

from .dialects import check_supported_profiles
from .errors import SqlError

API_VERSION = 1
"""The API version of `parser/library.h` that this binding implements."""
RESULT_OK = 0
"""The call made a document."""
RESULT_UNKNOWN_GRAMMAR = 1
"""The library has no grammar with the given identity; the call made no document."""
Json = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
"""A decoded JSON value of the library's documents."""
DocumentCall = Callable[["ctypes._Pointer[ctypes.c_char]", ctypes.c_size_t], int]
"""One C API call that writes a document pointer and its length, and returns a result code."""


class ParserLibraryError(Exception):
    """The library could not be loaded, or a call made no usable document."""


def library_name(platform: str) -> str:
    """Return the library's file name for a `sys.platform` value: a dylib on macOS, else a .so."""
    return "libsqlite-verifier-parser" + (".dylib" if platform == "darwin" else ".so")


def installed_library(root: Path, platform: str) -> Path:
    """Return the library's path in a verifier or conformance runtime root."""
    return root / "lib" / library_name(platform)


def check_metadata(metadata: Json, path: Path) -> None:
    """Refuse a library with another API version, or without a dialect for a supported profile."""
    if not isinstance(metadata, dict) or metadata.get("api") != API_VERSION:
        api = metadata.get("api") if isinstance(metadata, dict) else None
        raise ParserLibraryError(f"The parser library {path} has API {api!r}, but this verifier "
                                 f"needs API {API_VERSION}; reinstall the verifier")
    try:
        check_supported_profiles(metadata)
    except (SqlError, ValueError, KeyError, TypeError) as error:
        raise ParserLibraryError(f"The parser library {path} cannot parse a supported profile: "
                                 f"{error}; reinstall the verifier") from error


class ParserLibrary:
    """One loaded parser library, its metadata, and the lock for its calls."""

    def __init__(self, path: Path) -> None:
        """Load the library from an absolute path and check its API version."""
        if not path.is_absolute():
            raise ParserLibraryError(f"Parser library path {path} is relative; give the installed path")
        try:
            self._library = ctypes.CDLL(str(path))
        except OSError as error:
            raise ParserLibraryError(f"Cannot load the parser library {path}: {error}; "
                                     "rebuild or reinstall the verifier") from error
        self.path = path
        self._lock = Lock()
        document = ctypes.POINTER(ctypes.c_char)
        self._library.sqlite_verifier_parser_metadata.argtypes = [
            ctypes.POINTER(document), ctypes.POINTER(ctypes.c_size_t)]
        self._library.sqlite_verifier_parser_parse.argtypes = [
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(document),
            ctypes.POINTER(ctypes.c_size_t)]
        self._library.sqlite_verifier_parser_free.argtypes = [document]
        self._library.sqlite_verifier_parser_free.restype = None
        self.metadata = self._document("metadata", lambda result, size: self._library.sqlite_verifier_parser_metadata(
            ctypes.byref(result), ctypes.byref(size)))
        check_metadata(self.metadata, path)

    def _document(self, name: str, call: DocumentCall) -> Json:
        """Make one call under the lock and decode its document, or fail with the result code."""
        result = ctypes.POINTER(ctypes.c_char)()
        size = ctypes.c_size_t()
        with self._lock:
            code = call(result, size)
            if code != RESULT_OK:
                raise ParserLibraryError(f"The parser library's {name} call failed with result {code}"
                                         + (": unknown grammar" if code == RESULT_UNKNOWN_GRAMMAR else ""))
            try:
                data = ctypes.string_at(result, size.value)
            finally:
                self._library.sqlite_verifier_parser_free(result)
        try:
            return json.loads(data)
        except ValueError as error:
            raise ParserLibraryError(f"The parser library's {name} document is not JSON: {error}") from error

    def parse(self, grammar: str, sql: bytes) -> Json:
        """Parse sql with the grammar whose identity is grammar, and return the parse document."""
        identity = grammar.encode("ascii")
        return self._document("parse", lambda result, size: self._library.sqlite_verifier_parser_parse(
            identity, sql, len(sql), ctypes.byref(result), ctypes.byref(size)))


_loaded: dict[Path, ParserLibrary] = {}
"""The libraries that this process has loaded, by resolved path."""
_loading = Lock()
"""Serializes the first load of each path."""


def load(path: Path) -> ParserLibrary:
    """Return the library at path, loading it on the first call in this process."""
    with _loading:
        try:
            resolved = path.resolve(strict=True) if path.is_absolute() else path
        except OSError as error:
            raise ParserLibraryError(f"The parser library {path} is missing; rebuild or reinstall "
                                     "the verifier") from error
        if resolved not in _loaded:
            _loaded[resolved] = ParserLibrary(resolved)
        return _loaded[resolved]
