"""The build steps of the parser library check each release, grammar and library input.

These tests check `parser/library_steps.py`, which the derivations of
`build-support/parser-library.nix` run, with synthetic release directories and Lemon
outputs. The suite `parserLibrary` checks the library that the real steps build.
"""

from pathlib import Path

import pytest

from parser.dialect_table import Dialect, DialectTable, Release, grammar_identity
from parser.grammar_sources import read_release
from parser.library_metadata import Grammar, ReleaseRecord
from parser.library_steps import grammar_record, library_sources, read_release_record, release_record
from tests.parser_release_fixtures import release

pytestmark = [pytest.mark.unit, pytest.mark.parser]
PREPROCESSED = "input ::= cmd."
"""A stand-in for Lemon's preprocessed grammar."""


def test_release_step_checks_each_dialect_of_its_release(tmp_path: Path) -> None:
    """The step records the release and fails for an identity that the sources do not give."""
    directory = release(tmp_path / "upstream")
    identity = grammar_identity(PREPROCESSED, read_release(directory), ())
    table = DialectTable((Release("3.51.0", "upstream"),), (Dialect("3.51.0", (), identity),))
    record = release_record(directory, table, PREPROCESSED)
    assert record == ReleaseRecord("3.51.0", "2025-11-04 source", read_release(directory).grammar_options)
    changed = DialectTable(table.releases, (Dialect("3.51.0", (), "0" * 64),))
    with pytest.raises(ValueError, match="records 0000"):
        release_record(directory, changed, PREPROCESSED)
    with pytest.raises(ValueError, match="must pass only the release"):
        release_record(directory, DialectTable(table.releases * 2, table.dialects), PREPROCESSED)


def test_grammar_step_compares_the_production_count(tmp_path: Path) -> None:
    """A generated parser with another production count than Lemon's export fails the step."""
    (tmp_path / "syntax.c").write_text("#define YYNRULE              2\n")
    (tmp_path / "syntax.h").write_text("#define P_SEMI 1\n")
    (tmp_path / "grammar.y").write_text("input ::= cmd.\ncmd ::= SEMI.\n")
    assert grammar_record(tmp_path, "ab" * 32, "Syntax_ab") == Grammar("ab" * 32, "Syntax_ab", 2, 1)
    (tmp_path / "grammar.y").write_text("input ::= cmd.\n")
    with pytest.raises(ValueError, match="has 2 productions"):
        grammar_record(tmp_path, "ab" * 32, "Syntax_ab")


def test_sources_step_needs_every_grammar_once_with_a_unique_prefix(tmp_path: Path) -> None:
    """The library inputs are written only for the table's grammars, with distinct prefixes."""
    table = DialectTable((Release("3.51.0", "upstream"),), (Dialect("3.51.0", (), "ab" * 32),))
    releases = [ReleaseRecord("3.51.0", "source", ())]
    grammar = Grammar("ab" * 32, "Syntax_ab", 409, 186)
    library_sources(table, releases, [grammar], tmp_path)
    assert (tmp_path / "library_metadata.inc").is_file()
    with pytest.raises(ValueError, match="one grammar for each identity"):
        library_sources(table, releases, [], tmp_path)
    other = DialectTable(table.releases, (*table.dialects, Dialect("3.51.0", ("SQLITE_X",), "cd" * 32)))
    with pytest.raises(ValueError, match="same symbol prefix"):
        library_sources(other, releases, [grammar, Grammar("cd" * 32, "Syntax_ab", 409, 186)], tmp_path)
    with pytest.raises(ValueError, match="in the table.s order"):
        library_sources(table, [], [grammar], tmp_path)


def test_release_record_round_trip(tmp_path: Path) -> None:
    """A release record that one derivation writes is read back unchanged by the library step."""
    path = tmp_path / "release.json"
    path.write_text('{"version": "3.51.0", "source_id": "id", "grammar_options": ["SQLITE_A"]}')
    assert read_release_record(path) == ReleaseRecord("3.51.0", "id", ("SQLITE_A",))
