"""Run the parser library through `tests/parser_library_driver.c`, for `tests/parser_library_test.py`.

The suite's runtime root (`testRoot` in `build-support/parser-library.nix`) contains the
library, the driver built for it, the input records and, on Linux, the sanitized library
with its sanitized driver. The driver loads the
library in one process, as the verifier will, and writes each result to a file.
"""

from dataclasses import dataclass
import json
from pathlib import Path
import struct
import sys

from tests.runtime_support import run_command

LIBRARY_NAME = "libsqlite-verifier-parser" + (".dylib" if sys.platform == "darwin" else ".so")
"""The file name of the library on this platform."""
DRIVER_TIMEOUT_SECONDS = 120
"""One driver run over all inputs and grammars; the sanitized build needs about 6 seconds."""


@dataclass(frozen=True)
class Build:
    """A library and the driver built with the same compiler flags."""

    library: Path
    driver: Path

    @classmethod
    def at(cls, directory: Path) -> "Build":
        """Return the build whose `lib` and `bin` directories are in directory."""
        return cls(directory / "lib" / LIBRARY_NAME, directory / "bin/parser-library-driver")


@dataclass(frozen=True)
class Result:
    """The result code of one library call and its document; code 0 means a document."""

    code: int
    document: bytes


def metadata(build: Build, tmp_path: Path) -> dict[str, object]:
    """Return the metadata document that the library gives."""
    result = run_command([build.driver, build.library, "metadata"], cwd=tmp_path, timeout=DRIVER_TIMEOUT_SECONDS)
    assert result.returncode == 0, result.diagnostic()
    return result.json_object()


def parse_all(build: Build, inputs: Path, grammars: list[str], tmp_path: Path,
              environment: dict[str, str] | None = None) -> list[list[Result]]:
    """Parse every input record with each grammar in one driver process; return results per grammar."""
    output = tmp_path / "results"
    result = run_command([build.driver, build.library, "parse", inputs, output, *grammars],
                         cwd=tmp_path, timeout=DRIVER_TIMEOUT_SECONDS, environment=environment)
    assert result.returncode == 0 and not result.stderr, result.diagnostic()
    data = output.read_bytes()
    results: list[Result] = []
    offset = 0
    while offset < len(data):
        code, size = struct.unpack_from("<II", data, offset)
        results.append(Result(code, data[offset + 8:offset + 8 + size]))
        offset += 8 + size
    count = len(results) // len(grammars)
    return [results[index * count:(index + 1) * count] for index in range(len(grammars))]


def default_dialects(document: dict[str, object]) -> dict[str, str]:
    """Return the grammar identity of each release's default dialect."""
    dialects = document["dialects"]
    assert isinstance(dialects, list)
    return {dialect["version"]: dialect["grammar"] for dialect in dialects if not dialect["grammarOptions"]}


def parsed_status(result: Result) -> str | None:
    """Return the status of a document, or None for a call that made no document."""
    return json.loads(result.document)["status"] if result.code == 0 else None
