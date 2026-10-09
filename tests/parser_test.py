"""Independently selectable grammar recognition and source-bound syntax trees."""

from pathlib import Path
from tempfile import TemporaryDirectory

import pytest

from tests.parser_inputs import INVALID, OVERSIZED, RAISE_EXPRESSION, UNICODE_SPANS, VALID
from tests.runtime_support import run_command

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]
VERSIONS = ("3.51.0", "3.46.0")


def parse(sql: bytes, expected: str = "PARSED", *, runtime: Path, version: str) -> dict[str, object]:
    """Check status, exit, profile and every span using the explicitly selected binary."""
    name = "sqlite-parser" if version == "3.51.0" else "sqlite-parser-3.46.0"
    with TemporaryDirectory(prefix="parser-case-") as directory:
        path = Path(directory) / "input.sql"
        path.write_bytes(sql)
        result = run_command([str(runtime / "build" / name), str(path)],
                             cwd=runtime, timeout=3)
    value = result.json_object()
    assert value["status"] == expected, result.diagnostic()
    assert result.returncode == (0 if expected == "PARSED" else 1), result.diagnostic()
    if expected == "PARSED":
        assert value["profile"] == version, value
        nodes = value["nodes"]
        assert isinstance(nodes, list)
        for node in nodes:
            assert 0 <= node["start"] <= node["end"] <= len(sql), node
            assert all(0 <= child < len(nodes) for child in node["children"])
        assert nodes[value["root"]]["symbol"] == "input"
    return value


@pytest.mark.parametrize("version,sql", [(version, sql) for version in VERSIONS for _, sql in VALID],
                         ids=[f"{version}-{name}" for version in VERSIONS for name, _ in VALID])
def test_valid_grammar(version: str, sql: bytes, runtime_root: Path) -> None:
    """A grammar-family script parses with valid byte spans and the selected release."""
    parse(sql, runtime=runtime_root, version=version)


@pytest.mark.parametrize("version,sql", [(version, sql) for version in VERSIONS for _, sql in INVALID],
                         ids=[f"{version}-{name}" for version in VERSIONS for name, _ in INVALID])
def test_invalid_grammar(version: str, sql: bytes, runtime_root: Path) -> None:
    """Malformed bytes or syntax produce INPUT_ERROR and a nonzero parser exit."""
    parse(sql, "INPUT_ERROR", runtime=runtime_root, version=version)


@pytest.mark.parametrize("version", VERSIONS)
def test_resource_limit(version: str, runtime_root: Path) -> None:
    """An oversized SQL file produces the distinct RESOURCE_LIMIT parser result."""
    parse(OVERSIZED, "RESOURCE_LIMIT", runtime=runtime_root,
          version=version)


@pytest.mark.parametrize("version", VERSIONS)
def test_deterministic_unicode_spans(version: str, runtime_root: Path) -> None:
    """Repeated Unicode parsing preserves exact quoted byte spans and all CST output in both releases."""
    text = UNICODE_SPANS
    result = parse(text, runtime=runtime_root, version=version)
    assert result == parse(text, runtime=runtime_root, version=version)
    nodes = result["nodes"]
    assert isinstance(nodes, list)
    quoted = [text[node["start"]:node["end"]] for node in nodes if node["symbol"] == "ID"]
    assert '"café"'.encode() in quoted and '"💡"'.encode() in quoted, quoted



@pytest.mark.parametrize("version", VERSIONS)
def test_raise_expression_version_boundary(version: str, runtime_root: Path) -> None:
    """An expression in RAISE (added after 3.46) parses only in the newer pinned grammar."""
    parse(RAISE_EXPRESSION, "PARSED" if version == "3.51.0" else "INPUT_ERROR", runtime=runtime_root, version=version)
