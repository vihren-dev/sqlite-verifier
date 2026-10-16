"""The frontend maps parser productions to statement syntax and keeps source ranges.

These tests check `belay.sqlite.syntax` and its modules against the pinned parser
library: the JSON that Lean's `Syntax.Statement` decoder reads, the lexical
decoding of names and literals, the refusal of syntax without a constructor, and
the byte range that a Lean node path selects.
"""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from belay.sqlite.located import Located
from belay.sqlite.profiles import DEFAULT_PROFILE
from belay.sqlite.sql_tree import Node, Tree
from belay.sqlite.syntax import script_record, statements
from belay.sqlite.syntax_expressions import dequote
from belay.sqlite.syntax_writes import value_rows

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


def mapped(parse_sql: Callable[..., Tree], sql: str) -> list[object]:
    """Return the syntax JSON of every statement of the SQL."""
    return [item.value for item in statements(parse_sql(sql))]


def column(name: str, declared: str | None, constraints: list[object] | None = None) -> dict[str, object]:
    """The JSON of one column definition."""
    return {"name": name, "declaredType": declared, "constraints": constraints or []}


def test_definitions_keep_names_types_and_constraints_as_written(parse_sql: Callable[..., Tree]) -> None:
    """Names keep their case, types keep SQLite's dequoted span, and every constraint maps."""
    sql = ('CREATE TABLE [Big T](a VARCHAR ( 10 ) NOT NULL PRIMARY KEY DESC, "B" "Some" Type UNIQUE, '
           "c DEFAULT -1, d DEFAULT CURRENT_TIMESTAMP, e DEFAULT 'x''y', f, PRIMARY KEY(a), UNIQUE(c, d));"
           "CREATE UNIQUE INDEX i ON `Big T`(a, B); ALTER TABLE t ADD COLUMN z INT DEFAULT y;")
    assert mapped(parse_sql, sql) == [
        {"createTable": {"name": "Big T", "columns": [
            column("a", "VARCHAR ( 10 )", [{"notNull": {"algorithm": None}},
                                           {"primaryKey": {"descending": True, "algorithm": None}}]),
            column("B", "Some", [{"unique": {"algorithm": None}}]),
            column("c", None, [{"default": {"value": {"negate": {"operand": {"numeric": {"text": "1"}}}}}}]),
            column("d", None, [{"default": {"value": {"currentTime": {"keyword": "CURRENT_TIMESTAMP"}}}}]),
            column("e", None, [{"default": {"value": {"string": {"bytes": list(b"x'y")}}}}]),
            column("f", None)],
            "constraints": [{"primaryKey": {"columns": ["a"], "algorithm": None}},
                            {"unique": {"columns": ["c", "d"], "algorithm": None}}]}},
        {"createIndex": {"name": "i", "unique": True, "table": "Big T", "columns": ["a", "B"]}},
        {"addColumn": {"table": "t", "column": column("z", "INT", [
            {"default": {"value": {"identifier": {"name": "y", "doubleQuoted": False}}}}])}}]


def test_writes_keep_rows_assignments_and_numeric_text(parse_sql: Callable[..., Tree]) -> None:
    """INSERT keeps its optional columns and rows, with no ON CONFLICT clauses; UPDATE keeps
    assignments and its filter."""
    sql = ("BEGIN DEFERRED TRANSACTION; INSERT INTO t VALUES (0x1F, \"q\"), (NULL, X'00ff'); "
           "INSERT INTO t(a) VALUES (+1_000); UPDATE t SET a = -2.5, b = 'é' WHERE id == 3; "
           "UPDATE t SET a = 1; END; ROLLBACK TRANSACTION;")
    assert mapped(parse_sql, sql) == [
        "begin",
        {"insert": {"table": "t", "columns": None, "rows": [
            [{"numeric": {"text": "0x1F"}}, {"identifier": {"name": "q", "doubleQuoted": True}}],
            ["null", {"blob": {"bytes": [0, 255]}}]], "conflicts": [], "algorithm": None}},
        {"insert": {"table": "t", "columns": ["a"], "rows": [
            [{"positive": {"operand": {"numeric": {"text": "1_000"}}}}]], "conflicts": [], "algorithm": None}},
        {"update": {"table": "t", "assignments": [
            ["a", {"negate": {"operand": {"numeric": {"text": "2.5"}}}}],
            ["b", {"string": {"bytes": list("é".encode())}}]],
            "filter": {"equals": {"left": {"identifier": {"name": "id", "doubleQuoted": False}},
                                  "right": {"numeric": {"text": "3"}}}}}},
        {"update": {"table": "t", "assignments": [["a", {"numeric": {"text": "1"}}]], "filter": None}},
        "commit", "rollback"]


@pytest.mark.parametrize(("sql", "refused"), [
    ("CREATE TEMP TABLE t(a);", "TEMP"), ("CREATE TABLE IF NOT EXISTS t(a);", "IF NOT EXISTS"),
    ("CREATE TABLE main.t(a);", ".t"), ("CREATE TABLE t(a) STRICT;", "STRICT"),
    ("CREATE TABLE t AS SELECT 1;", "AS SELECT 1"), ("CREATE TABLE t(a COLLATE NOCASE);", "COLLATE NOCASE"),
    ("CREATE TABLE t(a CHECK (a));", "CHECK (a)"), ("CREATE TABLE t(a, PRIMARY KEY(a DESC));", "DESC"),
    ("CREATE TABLE t(a DEFAULT (1));", "DEFAULT (1)"), ("CREATE INDEX i ON t(a) WHERE a;", "WHERE a"),
    ("ALTER TABLE t RENAME TO u;", "ALTER TABLE t RENAME TO u"), ("BEGIN IMMEDIATE;", "IMMEDIATE"),
    ("UPDATE OR REPLACE t SET a = 1;", "OR REPLACE"), ("INSERT INTO t SELECT 1;", "SELECT 1"),
    ("INSERT INTO t VALUES (a || 1);", "a || 1"), ("UPDATE t SET a = 1 WHERE a IN (1);", "a IN (1)"),
    ("UPDATE t SET (a, b) = (1, 2);", "(a, b) = (1, 2)"), ("SELECT 1;", "SELECT 1"),
    ("EXPLAIN SELECT 1;", "EXPLAIN SELECT 1;"),
])
def test_syntax_without_a_constructor_is_unsupported_at_its_range(
        parse_sql: Callable[..., Tree], sql: str, refused: str) -> None:
    """Each refusal is UNSUPPORTED and its byte range is the refused syntax."""
    with pytest.raises(SqlError) as raised:
        statements(parse_sql(sql))
    assert raised.value.status == "UNSUPPORTED"
    assert sql.encode()[raised.value.start:raised.value.end].decode() == refused


@pytest.mark.parametrize(("sql", "advice"), [
    ("ALTER TABLE t RENAME TO u;", "rewrite it with the modeled forms: CREATE TABLE"),
    ("UPDATE t SET (a, b) = (1, 2);", "rewrite it with the modeled forms: CREATE TABLE"),
    ("INSERT INTO t SELECT 1;", "write INSERT ... VALUES (...)"),
    ("CREATE TABLE t(a COLLATE NOCASE);", "use NOT NULL, PRIMARY KEY, UNIQUE or DEFAULT with a literal"),
    ("SELECT 1;", "select from a table"),
    ("VACUUM;", "the model runs CREATE TABLE"),
])
def test_refusals_say_which_form_to_use(parse_sql: Callable[..., Tree], sql: str, advice: str) -> None:
    """Refusals from `require`, `left_list`, `value_rows` and the dispatch name the modeled forms."""
    with pytest.raises(SqlError) as raised:
        statements(parse_sql(sql))
    assert advice in str(raised.value)


def test_malformed_values_list_names_the_modeled_forms() -> None:
    """`value_rows` refuses a VALUES list node with a shape that the grammar does not produce."""
    nodes = (Node("COMMA", 0, 1, ()), Node("mvalues", 0, 1, (0,)), Node("oneselect", 0, 1, (1,)),
             Node("selectnowith", 0, 1, (2,)), Node("select", 0, 1, (3,)))
    with pytest.raises(SqlError) as raised:
        value_rows(Tree("fixture.sql", b",", nodes, 4), nodes[4])
    assert raised.value.status == "UNSUPPORTED"
    assert "rewrite it with the modeled forms" in str(raised.value)


def test_node_paths_select_source_ranges(parse_sql: Callable[..., Tree]) -> None:
    """A Lean restriction path selects the range of the node it names, or of its deepest known part."""
    sql = "CREATE TABLE t(a, rowid TEXT); INSERT INTO t(a) VALUES (1), (2.5); UPDATE t SET a = 1, b = -x;"
    create, insert, update = statements(parse_sql(sql))
    text = sql.encode()

    def at(located: Located, path: list[int]) -> str:
        """Return the source text of the range that `Located.span` selects for the path."""
        start, end = located.span(path)
        return text[start:end].decode()
    assert at(create, [1, 1]) == "rowid TEXT"
    assert at(insert, [2, 1, 0]) == "2.5"
    assert at(update, [1, 1, 1, 0]) == "x"
    assert at(update, [1, 1, 1, 0, 9]) == "x"


def test_dequote_follows_sqlite() -> None:
    """Doubled quotes are undoubled, brackets do not escape, and text ends at the closing quote."""
    assert [dequote(text) for text in ['"a""b"', "[a]]", "`x`", "'it''s'", '"Some" Type', "plain"]] == [
        'a"b', "a]", "x", "it's", "Some", "plain"]


def test_record_names_the_profile_and_both_scripts(parse_sql: Callable[..., Tree]) -> None:
    """The record carries version 2, the release and build, and the statement JSON."""
    schema = statements(parse_sql("CREATE TABLE t(a);"))
    record = script_record(DEFAULT_PROFILE, schema, statements(parse_sql("COMMIT;")))
    assert record == {"version": 2, "release": "3.51.0", "sourceId": DEFAULT_PROFILE.source_id,
                      "schema": [schema[0].value], "script": ["commit"]}
