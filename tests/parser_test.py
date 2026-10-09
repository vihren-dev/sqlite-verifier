"""Grammar recognition and source-bound syntax trees of each grammar of the parser library.

The tests take the grammars and dialects from the library's metadata, so a new grammar
is tested without a test change. They parse through the binding in
`belay/sqlite/parser_library.py`.
"""

from pathlib import Path
import sys

import pytest

from belay.sqlite.parser_library import ParserLibrary, installed_library, load
from tests.parser_inputs import INVALID, OVERSIZED, RAISE_EXPRESSION, UNICODE_SPANS, VALID

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native("parser-library")]
RAISE_EXPRESSION_RELEASE = (3, 47, 0)
"""The first SQLite release that accepts an expression in RAISE."""


@pytest.fixture(scope="module")
def library(runtime_root: Path) -> ParserLibrary:
    """The runtime's parser library."""
    return load(installed_library(runtime_root.resolve(), sys.platform))


def default_dialects(library: ParserLibrary) -> dict[str, str]:
    """Return the grammar identity of each release's default dialect, from the metadata."""
    dialects = library.metadata["dialects"]  # type: ignore[index]
    return {dialect["version"]: dialect["grammar"] for dialect in dialects if not dialect["grammarOptions"]}


def check(library: ParserLibrary, grammar: str, sql: bytes, expected: str = "PARSED") -> dict[str, object]:
    """Check the status, the grammar and every span of one parse."""
    value = library.parse(grammar, sql)
    assert isinstance(value, dict) and value["status"] == expected, (grammar, sql[:200], value)
    if expected == "PARSED":
        assert value["grammar"] == grammar
        nodes = value["nodes"]
        assert isinstance(nodes, list)
        for node in nodes:
            assert 0 <= node["start"] <= node["end"] <= len(sql), node
            assert all(0 <= child < len(nodes) for child in node["children"])
        assert nodes[value["root"]]["symbol"] == "input"
    return value


@pytest.mark.parametrize("sql", [sql for _, sql in VALID], ids=[name for name, _ in VALID])
def test_valid_grammar(sql: bytes, library: ParserLibrary) -> None:
    """A grammar-family script parses with valid byte spans in every grammar."""
    for grammar in default_dialects(library).values():
        check(library, grammar, sql)


@pytest.mark.parametrize("sql", [sql for _, sql in INVALID], ids=[name for name, _ in INVALID])
def test_invalid_grammar(sql: bytes, library: ParserLibrary) -> None:
    """Malformed bytes or syntax give the INPUT_ERROR status in every grammar."""
    for grammar in default_dialects(library).values():
        check(library, grammar, sql, "INPUT_ERROR")


def test_resource_limit(library: ParserLibrary) -> None:
    """An oversized SQL text gives the distinct RESOURCE_LIMIT status in every grammar."""
    for grammar in default_dialects(library).values():
        check(library, grammar, OVERSIZED, "RESOURCE_LIMIT")


def test_deterministic_unicode_spans(library: ParserLibrary) -> None:
    """Repeated Unicode parsing keeps exact quoted byte spans and the whole tree in every grammar."""
    for grammar in default_dialects(library).values():
        result = check(library, grammar, UNICODE_SPANS)
        assert result == check(library, grammar, UNICODE_SPANS)
        nodes = result["nodes"]
        assert isinstance(nodes, list)
        quoted = [UNICODE_SPANS[node["start"]:node["end"]] for node in nodes if node["symbol"] == "ID"]
        assert '"café"'.encode() in quoted and '"💡"'.encode() in quoted, quoted


def test_raise_expression_version_boundary(library: ParserLibrary) -> None:
    """An expression in RAISE parses only in the grammars of SQLite 3.47 and later."""
    dialects = default_dialects(library)
    assert {"3.51.0", "3.46.0"} <= set(dialects)
    for version, grammar in dialects.items():
        accepted = tuple(int(part) for part in version.split(".")) >= RAISE_EXPRESSION_RELEASE
        check(library, grammar, RAISE_EXPRESSION, "PARSED" if accepted else "INPUT_ERROR")
