"""The parser library loads all grammars in one process and is free of memory faults.

These tests check the library that `build-support/parser-library.nix` builds from
`parser/library*.c` and `parser/dialects.json`: its metadata, its grammar selection in
one process, and its memory safety under the sanitizers.
"""

import os
from pathlib import Path
import sys

import pytest

from tests.parser_inputs import RAISE_EXPRESSION
from tests.parser_library_inputs import read_records, write_records
from tests.parser_library_support import Build, Result, default_dialects, metadata, parse_all, parsed_status

pytestmark = [pytest.mark.integration, pytest.mark.parser]
API_VERSION = 1
"""The API version of `parser/library.h`."""
RAISE_ACCEPTED = {"3.51.0": True, "3.46.0": False}
"""Whether each release accepts an expression in RAISE, which SQLite 3.47 added."""
UNKNOWN_GRAMMAR = "0" * 64
"""A grammar identity that no library contains."""
SANITIZER_ENVIRONMENT = {"ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1",
                         "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"}
"""Stop the sanitized driver at the first finding, including a leak at exit."""


@pytest.fixture(scope="module")
def build(runtime_root: Path) -> Build:
    """The library and driver built with the normal flags."""
    return Build.at(runtime_root)


def test_metadata_has_a_grammar_for_each_dialect(build: Build, tmp_path: Path) -> None:
    """`metadata` gives the API version, both releases, and a listed grammar for each dialect."""
    document = metadata(build, tmp_path)
    assert document["api"] == API_VERSION
    grammars = document["grammars"]
    assert isinstance(grammars, list)
    assert set(default_dialects(document)) == set(RAISE_ACCEPTED)
    assert set(default_dialects(document).values()) == {grammar["grammar"] for grammar in grammars}
    assert all(grammar["productions"] > 0 and grammar["tokens"] > 0 for grammar in grammars)


def test_one_process_parses_with_each_grammar(build: Build, tmp_path: Path) -> None:
    """One process parses the RAISE case with every grammar, and each release gives its own result.
    An unknown grammar identity gives result code 1 and no document."""
    dialects = default_dialects(metadata(build, tmp_path))
    inputs = tmp_path / "inputs"
    write_records(inputs, [RAISE_EXPRESSION])
    versions = sorted(dialects)
    results = parse_all(build, inputs, [dialects[version] for version in versions] + [UNKNOWN_GRAMMAR], tmp_path)
    for version, [result] in zip(versions, results):
        assert parsed_status(result) == ("PARSED" if RAISE_ACCEPTED[version] else "INPUT_ERROR"), (version, result)
    assert results[-1] == [Result(1, b"")]


@pytest.mark.skipif(not sys.platform.startswith("linux"), reason="the sanitizer job runs on Linux amd64 only")
def test_sanitizers_find_nothing(runtime_root: Path, tmp_path: Path) -> None:
    """The sanitized library parses every input with every grammar without an AddressSanitizer,
    LeakSanitizer or UndefinedBehaviorSanitizer finding; a finding stops the driver."""
    sanitized = Build.at(runtime_root / "sanitized")
    grammars = [grammar["grammar"] for grammar in metadata(sanitized, tmp_path)["grammars"]]
    inputs = runtime_root / "inputs"
    environment = {**os.environ, **SANITIZER_ENVIRONMENT}
    results = parse_all(sanitized, inputs, grammars, tmp_path, environment)
    assert [len(outputs) for outputs in results] == [len(read_records(inputs))] * len(grammars)
    assert all(result.code == 0 for outputs in results for result in outputs)
