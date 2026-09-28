"""Independently selectable grammar recognition and source-bound syntax trees."""

from pathlib import Path
from tempfile import TemporaryDirectory
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tests.runtime_support import run_command
pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]
VERSIONS = ("3.51.0", "3.46.0")
VALID = (
    ('empty', b''),
    ('line_comment', b'-- only a comment'),
    ('comment_semicolons', b'/* comment */ ; ;'),
    ('create_add', b'CREATE TABLE t(a TEXT); ALTER TABLE t ADD COLUMN b INTEGER;'),
    ('quoted_names', b"CREATE TABLE 'quoted name'([x;y] TEXT, `z``a` BLOB);"),
    ('trigger_semicolons', b"CREATE TRIGGER tr AFTER INSERT ON missing BEGIN SELECT 'a;b'; SELECT 2; END; SELECT 3;"),
    ('literal_tokens', b"SELECT ';', 'it''s', X'00FF', 1_000, ?1, :named; -- end"),
    ('contextual_keywords', b'CREATE TABLE window(over, filter, key); SELECT over, filter FROM window;'),
    ('window_filter', b'SELECT sum(x) FILTER (WHERE x>0) OVER (PARTITION BY a ORDER BY b) FROM absent;'),
    ('named_window', b'SELECT sum(x) OVER win FROM absent WINDOW win AS (ORDER BY x);'),
    ('recursive_cte', b'WITH RECURSIVE c(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM c WHERE x<3) SELECT * FROM c;'),
    ('upsert_returning', b'INSERT INTO absent(a) VALUES(1) ON CONFLICT(a) DO UPDATE SET a=excluded.a RETURNING a;'),
    ('virtual_table', b"CREATE VIRTUAL TABLE absent USING uninstalled(a, tokenize='porter unicode61');"),
    ('strict_generated', b"CREATE TABLE s(id INTEGER PRIMARY KEY, x TEXT GENERATED ALWAYS AS ('x')) STRICT;"),
    ('expression_index', b'CREATE INDEX i ON absent((x+1)) WHERE x IS NOT NULL;'),
    ('attach_pragma_vacuum', b"ATTACH ':memory:' AS aux; DETACH aux; PRAGMA main.user_version=1; VACUUM;"),
    ('transaction_savepoint', b'BEGIN IMMEDIATE; SAVEPOINT s; ROLLBACK TO s; RELEASE s; COMMIT;'),
    ('explain_delete', b'EXPLAIN QUERY PLAN SELECT * FROM missing; DELETE FROM missing RETURNING *;'),
    ('update_analyze_reindex', b'UPDATE missing SET a=1 WHERE a=0 RETURNING a; ANALYZE missing; REINDEX;'),
    ('unicode_bom', b'\xef\xbb\xbfCREATE TABLE "caf\xc3\xa9"("\xd0\xbd\xd0\xb0\xd0\xbc\xd0\xb5" TEXT); /*\xe7\xb5\x82*/ ALTER TABLE "caf\xc3\xa9" ADD "\xf0\x9f\x92\xa1";'),
)
INVALID = (
    ('incomplete_select', b'SELECT'),
    ('incomplete_create', b'CREATE TABLE t('),
    ('unterminated_string', b"SELECT 'unterminated"),
    ('odd_blob', b"SELECT X'odd'"),
    ('trailing_nonsense', b'CREATE TABLE t(a); nonsense;'),
    ('embedded_nul', b'SELECT 1\x00; DROP TABLE t;'),
    ('invalid_utf8', b"SELECT '\xff';"),
    ('incomplete_trigger', b'CREATE TRIGGER t AFTER INSERT ON x BEGIN SELECT 1;'),
    ('update_limit', b'UPDATE t SET a=1 LIMIT 1'),
    ('invalid_variable', b'SELECT @;'),
    ('utf8_surrogate', b"SELECT '\xed\xa0\x80';"),
    ('double_separator', b'SELECT 1__2'),
    ('trailing_separator', b'SELECT 1_'),
    ('hex_double_separator', b'SELECT 0xA__B'),
    ('separator_before_decimal', b'SELECT 1_.2'),
)


def parse(sql: bytes, expected: str = "PARSED", *, runtime: Path, version: str,
          artifacts: Path | None = None) -> dict[str, object]:
    """Check status, exit, profile and every span using the explicitly selected binary."""
    name = "sqlite-parser" if version == "3.51.0" else "sqlite-parser-3.46.0"
    with TemporaryDirectory(prefix="parser-case-") as directory:
        path = Path(directory) / "input.sql"
        path.write_bytes(sql)
        result = run_command([str(runtime / "build" / name), str(path)],
                             cwd=runtime, timeout=3, artifacts=artifacts)
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
def test_valid_grammar(version: str, sql: bytes, runtime_root: Path, case_artifacts: Path) -> None:
    """A grammar-family script parses with valid byte spans and the selected release."""
    parse(sql, runtime=runtime_root, version=version, artifacts=case_artifacts)


@pytest.mark.parametrize("version,sql", [(version, sql) for version in VERSIONS for _, sql in INVALID],
                         ids=[f"{version}-{name}" for version in VERSIONS for name, _ in INVALID])
def test_invalid_grammar(version: str, sql: bytes, runtime_root: Path, case_artifacts: Path) -> None:
    """Malformed bytes or syntax produce INPUT_ERROR and a nonzero parser exit."""
    parse(sql, "INPUT_ERROR", runtime=runtime_root, version=version, artifacts=case_artifacts)


@pytest.mark.parametrize("version", VERSIONS)
def test_resource_limit(version: str, runtime_root: Path, case_artifacts: Path) -> None:
    """An oversized SQL file produces the distinct RESOURCE_LIMIT parser result."""
    parse(b" " * (1024 * 1024 + 1), "RESOURCE_LIMIT", runtime=runtime_root,
          version=version, artifacts=case_artifacts)


def unicode_spans(runtime: Path, version: str, artifacts: Path | None = None) -> None:
    """Repeated Unicode parsing preserves exact quoted byte spans and all CST output."""
    text = 'CREATE TABLE "café"("💡" TEXT);'.encode()
    result = parse(text, runtime=runtime, version=version, artifacts=artifacts)
    assert result == parse(text, runtime=runtime, version=version, artifacts=artifacts)
    nodes = result["nodes"]
    assert isinstance(nodes, list)
    quoted = [text[node["start"]:node["end"]] for node in nodes if node["symbol"] == "ID"]
    assert '"café"'.encode() in quoted and '"💡"'.encode() in quoted, quoted


@pytest.mark.parametrize("version", VERSIONS)
def test_deterministic_unicode_spans(version: str, runtime_root: Path, case_artifacts: Path) -> None:
    """Unicode identifiers have deterministic source-bound trees in both releases."""
    unicode_spans(runtime_root, version, case_artifacts)


def raise_expression(runtime: Path, version: str, artifacts: Path | None = None) -> None:
    """RAISE expressions introduced after 3.46 distinguish the actual selected grammars."""
    parse(b"CREATE TRIGGER tr BEFORE INSERT ON t BEGIN SELECT RAISE(FAIL, 1+2); END;",
          "PARSED" if version == "3.51.0" else "INPUT_ERROR", runtime=runtime,
          version=version, artifacts=artifacts)


@pytest.mark.parametrize("version", VERSIONS)
def test_raise_expression_version_boundary(version: str, runtime_root: Path, case_artifacts: Path) -> None:
    """An expression in RAISE parses only in the newer pinned grammar."""
    raise_expression(runtime_root, version, case_artifacts)


def check(runtime: Path, version: str) -> None:
    """Produce the legacy grammar evidence denominator until aggregation moves to pytest."""
    for _, sql in VALID:
        parse(sql, runtime=runtime, version=version)
    for _, sql in INVALID:
        parse(sql, "INPUT_ERROR", runtime=runtime, version=version)
    parse(b" " * (1024 * 1024 + 1), "RESOURCE_LIMIT", runtime=runtime, version=version)
    unicode_spans(runtime, version)
    raise_expression(runtime, version)
    print(f"{version} parser checks passed: {len(VALID)} grammar scripts, malformed/limit and byte-span cases")


if __name__ == "__main__":
    for release in VERSIONS:
        check(ROOT, release)
