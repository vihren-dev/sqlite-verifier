"""End-to-end admission checks against the production upstream-derived parser."""

from collections.abc import Callable
from pathlib import Path

import pytest

from belay.sqlite.errors import SqlError
from belay.sqlite.quoted_text import quoted_string
from belay.sqlite.sql_model import transition
from migration_check.lean_inputs import sql_inputs
from belay.sqlite.sql_tree import SqlParser, Tree, parse
from belay.sqlite.translate import normalize, starting_schema, statements
from conformance.record_parser import default_parser

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]
UNSUPPORTED_STATEMENTS = [
    'CREATE TABLE t(x INTEGER PRIMARY KEY);', 'CREATE TABLE t(x);',
    'CREATE TABLE t(x VARCHAR(20));', 'CREATE TABLE t(x "TEXT");',
    'CREATE TABLE t(x TEXT NOT NULL);', 'CREATE TABLE t(x TEXT DEFAULT NULL);',
    'CREATE TABLE t(x TEXT COLLATE NOCASE);', 'CREATE TABLE t(x TEXT UNIQUE);',
    'CREATE TABLE t(x TEXT REFERENCES u);', 'CREATE TABLE t(x TEXT CHECK(x));',
    'CREATE TABLE t(x TEXT, UNIQUE(x));', 'CREATE TABLE t(x TEXT) STRICT;',
    'CREATE TEMP TABLE t(x TEXT);', 'CREATE TABLE main.t(x TEXT);',
    'CREATE TABLE IF NOT EXISTS t(x TEXT);', 'CREATE TABLE t AS SELECT 1;',
    'CREATE TABLE t(rowid TEXT);', 'CREATE TABLE sqlite_private(x TEXT);',
    'CREATE TABLE t(x TEXT, X TEXT);', 'ALTER TABLE main.t ADD x TEXT;',
    'ALTER TABLE t RENAME TO u;', 'ALTER TABLE t ADD x TEXT GENERATED AS (1);',
    'CREATE TABLE t(x TEXT); CREATE VIEW v AS SELECT * FROM t;',
    'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x);',
    'CREATE TABLE t(x TEXT); CREATE TRIGGER tr AFTER INSERT ON t BEGIN SELECT 1; END;',
    'PRAGMA foreign_keys=ON;', 'BEGIN IMMEDIATE; CREATE TABLE t(x TEXT); COMMIT;',
    'EXPLAIN CREATE TABLE t(x TEXT);', 'SELECT 1;',
]


def test_supported_scripts_and_prefix_failures(parse_sql: Callable[..., Tree]) -> None:
    """Quoted names and comments keep byte spans and sequential name resolution."""
    schema = starting_schema(parse_sql('CREATE TABLE "Café"("Имя" TEXT, n INTEGER);'))
    sql = '/* ; */ ALTER TABLE "Café" ADD "💡" BLOB; CREATE TABLE extra(r REAL, n NUMERIC);'
    script = statements(parse_sql(sql))
    after, failure = transition(schema, script)
    assert failure == ""
    assert [table.name for table in after] == ["café", "extra"]
    assert after[0].columns[-1].name == "💡"
    assert len(script) == 2
    assert sql.encode()[script[0].start:script[0].end].startswith(b"ALTER TABLE")
    broken = statements(parse_sql('ALTER TABLE "Café" ADD new TEXT; CREATE TABLE "CAFé"(x TEXT);'
                                  'CREATE TABLE skipped(x TEXT);'))
    prefix, error = transition(schema, broken)
    assert error == "tableExists"
    assert len(prefix) == 1 and prefix[0].columns[-1].name == "new"
    assert transition(schema, statements(parse_sql('ALTER TABLE absent ADD x TEXT;')))[1] == "missingTable"
    assert transition(schema, statements(parse_sql('ALTER TABLE "café" ADD N TEXT;')))[1] == "columnExists"
    assert 'def script : List Statement := [.addColumn "café"' in sql_inputs(schema, script)
    assert normalize("ÄZ") == "Äz"
    assert quoted_string('a\b\f"\\\n') == '"a\\u0008\\u000c\\"\\\\\\u000a"'


@pytest.mark.parametrize("sql", UNSUPPORTED_STATEMENTS)
def test_unsupported_statement(parse_sql: Callable[..., Tree], sql: str) -> None:
    """No valid but unmodeled object or optional SQL clause can disappear."""
    with pytest.raises(SqlError) as rejected:
        statements(parse_sql(sql))
    assert rejected.value.status == "UNSUPPORTED"


def test_duplicate_and_empty_schema(parse_sql: Callable[..., Tree]) -> None:
    """Case-insensitive duplicate tables are input errors; an empty schema has no tables."""
    with pytest.raises(SqlError) as duplicate:
        starting_schema(parse_sql('CREATE TABLE t(x TEXT); CREATE TABLE T(x TEXT);'))
    assert duplicate.value.status == "INPUT_ERROR"
    assert starting_schema(parse_sql('-- empty\n;')) == ()


def test_result_for_another_grammar_is_rejected(runtime_root: Path) -> None:
    """`parse` refuses a library document for another grammar than the one it requested."""
    parser = default_parser(runtime_root)

    class OtherGrammar:
        """A library whose documents name another grammar."""

        metadata = parser.library.metadata

        def parse(self, grammar: str, sql: bytes) -> object:
            """Return the real document with another grammar identity."""
            return {**parser.library.parse(grammar, sql), "grammar": "0" * 64}  # type: ignore[dict-item]

    with pytest.raises(SqlError) as rejected:
        parse(SqlParser(OtherGrammar(), parser.grammar), b'CREATE TABLE t(x TEXT);', 'fixture.sql')  # type: ignore[arg-type]
    assert rejected.value.status == 'UNVERIFIED'
    assert 'another grammar' in str(rejected.value)


@pytest.mark.parametrize("sql,status", [("CREATE TABLE", "INPUT_ERROR"), (" " * (1024 * 1024 + 1), "UNVERIFIED")],
                         ids=["syntax", "resource_limit"])
def test_parser_failure_classes(parse_sql: Callable[..., Tree], sql: str, status: str) -> None:
    """Resource exhaustion does not become a syntax error or a violated theorem."""
    with pytest.raises(SqlError) as rejected:
        parse_sql(sql)
    assert rejected.value.status == status
