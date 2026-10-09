"""Checks of the parser library build: the load test, the comparison and the sanitizer job.

Each check runs `tests/parser_library_driver.c` against a built library.

- `load`: one process loads the library and parses the RAISE case with each grammar.
  Each release's grammar gives its own result, and an unknown grammar gives the
  distinct error with no document. The metadata has the expected API version and
  lists a grammar for each dialect.
- `compare`: for each dialect, the library output equals the output of the executable
  of its release for every input, except that the grammar identity replaces the
  release. This check ends when the executables are removed.
- `sanitize`: a sanitized driver parses every input with each grammar of a sanitized
  library; the driver exits nonzero on a sanitizer finding.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests.parser_inputs import RAISE_EXPRESSION
from tests.parser_library_inputs import read_records, write_records

API_VERSION = 1
"""The API version of `parser/library.h` that these checks expect."""
EXECUTABLES = {"3.51.0": "sqlite-parser", "3.46.0": "sqlite-parser-3.46.0"}
"""The executable of each release that the comparison uses as its reference."""
RAISE_ACCEPTED = {"3.51.0": True, "3.46.0": False}
"""Whether each release's grammar accepts an expression in RAISE, which SQLite 3.47 added."""
UNKNOWN_GRAMMAR = "0" * 64
"""A grammar identity that no library contains."""
DRIVER_TIMEOUT_SECONDS = 300
"""The limit for one driver run over all inputs, with the sanitizers on."""
EXECUTABLE_TIMEOUT_SECONDS = 5
"""The limit for one executable run: the old parser deadline."""
Result = tuple[int, bytes]
"""The result code and the document of one library call."""


def metadata(driver: Path, library: Path) -> dict[str, object]:
    """Return the metadata document that the library gives through the driver."""
    result = subprocess.run([str(driver), str(library), "metadata"], capture_output=True,
                            timeout=DRIVER_TIMEOUT_SECONDS, check=True)
    return json.loads(result.stdout)


def parse_all(driver: Path, library: Path, inputs: Path, grammars: list[str]) -> list[list[Result]]:
    """Parse every input with each grammar in one driver process; return results per grammar."""
    with TemporaryDirectory(prefix="parser-library-") as directory:
        output = Path(directory) / "results"
        result = subprocess.run([str(driver), str(library), "parse", str(inputs), str(output), *grammars],
                                capture_output=True, text=True, timeout=DRIVER_TIMEOUT_SECONDS)
        if result.returncode or result.stderr:
            raise AssertionError(f"The driver failed with exit code {result.returncode}:\n{result.stderr}")
        data = output.read_bytes()
    results: list[Result] = []
    offset = 0
    while offset < len(data):
        code, size = struct.unpack_from("<II", data, offset)
        results.append((code, data[offset + 8:offset + 8 + size]))
        offset += 8 + size
    count = len(results) // len(grammars)
    return [results[index * count:(index + 1) * count] for index in range(len(grammars))]


def dialect_grammars(document: dict[str, object]) -> dict[str, str]:
    """Return the grammar identity of each release's default dialect, checking the metadata."""
    if document.get("api") != API_VERSION:
        raise AssertionError(f"The library has API {document.get('api')}, expected {API_VERSION}")
    grammars = {grammar["grammar"] for grammar in document["grammars"]}
    dialects = {dialect["version"]: dialect["grammar"] for dialect in document["dialects"]
                if not dialect["grammarOptions"]}
    if set(dialects.values()) != grammars:
        raise AssertionError(f"The dialects use the grammars {dialects}, but the library has {grammars}")
    return dialects


def check_load(driver: Path, library: Path) -> None:
    """Parse the RAISE case with all grammars and an unknown one in one process."""
    dialects = dialect_grammars(metadata(driver, library))
    if set(dialects) != set(RAISE_ACCEPTED):
        raise AssertionError(f"The library has dialects {sorted(dialects)}, expected {sorted(RAISE_ACCEPTED)}")
    with TemporaryDirectory(prefix="parser-library-") as directory:
        inputs = Path(directory) / "inputs"
        write_records(inputs, [RAISE_EXPRESSION])
        versions = sorted(dialects)
        results = parse_all(driver, library, inputs, [dialects[version] for version in versions] + [UNKNOWN_GRAMMAR])
    for version, [(code, document)] in zip(versions, results):
        status = json.loads(document)["status"] if code == 0 else None
        if status != ("PARSED" if RAISE_ACCEPTED[version] else "INPUT_ERROR"):
            raise AssertionError(f"The {version} grammar gives {code} {document!r} for the RAISE case")
    if results[-1] != [(1, b"")]:
        raise AssertionError(f"An unknown grammar gives {results[-1]}, expected code 1 and no document")
    print(f"One process parsed the RAISE case with the grammars of {', '.join(versions)}", flush=True)


def executable_output(executable: Path, sql: bytes) -> bytes:
    """Return the standard output of one executable run on sql."""
    with TemporaryDirectory(prefix="parser-executable-") as directory:
        path = Path(directory) / "input.sql"
        path.write_bytes(sql)
        result = subprocess.run([str(executable), str(path)], capture_output=True,
                                timeout=EXECUTABLE_TIMEOUT_SECONDS)
    if result.returncode not in (0, 1):
        raise AssertionError(f"{executable} failed with exit code {result.returncode}: {result.stderr!r}")
    return result.stdout


def check_compare(driver: Path, library: Path, inputs: Path, executables: Path) -> None:
    """Compare the library output with the executable output for every input and release."""
    dialects = dialect_grammars(metadata(driver, library))
    records = read_records(inputs)
    versions = sorted(dialects)
    results = parse_all(driver, library, inputs, [dialects[version] for version in versions])
    for version, outputs in zip(versions, results):
        executable = executables / EXECUTABLES[version]
        with ThreadPoolExecutor(os.cpu_count()) as pool:
            expected = list(pool.map(lambda sql: executable_output(executable, sql), records))
        release = f'{{"status":"PARSED","profile":"{version}",'.encode()
        identity = f'{{"status":"PARSED","grammar":"{dialects[version]}",'.encode()
        for sql, reference, (code, document) in zip(records, expected, outputs, strict=True):
            if reference.startswith(release):
                reference = identity + reference[len(release):]
            if code != 0 or document != reference:
                raise AssertionError(f"The {version} library output differs for {sql[:200]!r}:\n"
                                     f"library:    {code} {document[:300]!r}\nexecutable: {reference[:300]!r}")
        print(f"{version}: {len(records)} inputs give the same output", flush=True)


def check_sanitize(driver: Path, library: Path, inputs: Path) -> None:
    """Parse every input with each grammar; the sanitizers stop the driver on a finding."""
    grammars = [grammar["grammar"] for grammar in metadata(driver, library)["grammars"]]
    results = parse_all(driver, library, inputs, grammars)
    failed = [code for outputs in results for code, _ in outputs if code != 0]
    if failed or len(results[0]) != len(read_records(inputs)):
        raise AssertionError(f"The sanitized library gave {len(failed)} results without a document")
    print(f"{len(grammars)} grammars parsed {len(results[0])} inputs without a sanitizer finding", flush=True)


def main() -> None:
    """Run one check from the command line."""
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument("check", choices=("load", "compare", "sanitize"))
    cli.add_argument("--driver", type=Path, required=True)
    cli.add_argument("--library", type=Path, required=True)
    cli.add_argument("--inputs", type=Path)
    cli.add_argument("--executables", type=Path)
    arguments = cli.parse_args()
    if arguments.check == "load":
        check_load(arguments.driver, arguments.library)
    elif arguments.check == "compare":
        check_compare(arguments.driver, arguments.library, arguments.inputs, arguments.executables)
    else:
        check_sanitize(arguments.driver, arguments.library, arguments.inputs)


if __name__ == "__main__":
    main()
