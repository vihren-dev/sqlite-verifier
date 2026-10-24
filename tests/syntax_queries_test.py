"""The translation maps a single-table SELECT to statement syntax (`packages/belay-sqlite-text/Belay/Sqlite/Translation/Select.lean` and the
modules that it uses, through the text package's program).

These tests check the JSON that Lean's `Syntax.Statement.select` decoder reads, the
source text of result columns, the LIMIT forms, and the refusal of query syntax
outside slice 1 of ADR 0012 with its byte range.
"""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from conformance.sql_text import Translation

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


def column(name: str) -> dict[str, object]:
    """The JSON of an identifier written without double quotes."""
    return {"identifier": {"name": name, "quote": "none"}}


def test_select_keeps_columns_text_and_clauses(parse_sql: Callable[..., Translation]) -> None:
    """Every clause maps; a result column keeps its alias and its source text exactly."""
    [select] = [item.value for item in parse_sql(
        "SELECT *, a AS x, count(*), min(b), b  <>  1 FROM t WHERE a IS NOT NULL AND NOT b < 2 "
        "GROUP BY a ORDER BY 1 DESC, b LIMIT 1, 2;").statements()]
    assert select == {"select": {
        "columns": ["star",
                    {"expression": {"value": column("a"), "alias": "x", "text": "a"}},
                    {"expression": {"value": {"callStar": {"name": "count"}}, "alias": None, "text": "count(*)"}},
                    {"expression": {"value": {"call": {"name": "min", "arguments": [column("b")]}},
                                    "alias": None, "text": "min(b)"}},
                    {"expression": {"value": {"compare": {"operator": "ne", "left": column("b"),
                                                          "right": {"numeric": {"text": "1"}}}},
                                    "alias": None, "text": "b  <>  1"}}],
        "source": {"table": "t", "alias": None, "arguments": None, "query": None}, "joins": [],
        "filter": {"and": {"left": {"compare": {"operator": "isNot", "left": column("a"), "right": "null"}},
                           "right": {"not": {"operand": {"compare": {"operator": "lt", "left": column("b"),
                                                                     "right": {"numeric": {"text": "2"}}}}}}}},
        "groupBy": [column("a")],
        "orderBy": [{"expression": {"numeric": {"text": "1"}}, "descending": True},
                    {"expression": column("b"), "descending": False}],
        "limit": {"numeric": {"text": "2"}}, "offset": {"numeric": {"text": "1"}}}}


@pytest.mark.parametrize(("sql", "operand"), [
    ("SELECT a FROM t WHERE a ISNULL;", False), ("SELECT a FROM t WHERE a NOTNULL;", True),
    ("SELECT a FROM t WHERE a NOT NULL;", True),
])
def test_postfix_null_tests_map_to_is_null(parse_sql: Callable[..., Translation], sql: str, operand: bool) -> None:
    """`ISNULL`, `NOTNULL` and `NOT NULL` are `IS NULL` and its negation."""
    [select] = [item.value for item in parse_sql(sql).statements()]
    assert select["select"]["filter"] == {"isNull": {"operand": column("a"), "negated": operand}}


@pytest.mark.parametrize(("sql", "refused"), [
    ("SELECT main.t.a FROM t;", "main.t.a"),
    ("SELECT a FROM main.t;", ".t"), ("SELECT a FROM t ORDER BY a NULLS LAST;", "NULLS LAST"),
    ("SELECT count(DISTINCT a) FROM t;", "DISTINCT"),
    ("SELECT a & 1 FROM t;", "a & 1"),
])
def test_query_syntax_outside_the_slice_is_unsupported_at_its_range(
        parse_sql: Callable[..., Translation], sql: str, refused: str) -> None:
    """Each refusal is UNSUPPORTED, and its byte range is the refused syntax."""
    with pytest.raises(SqlError) as raised:
        parse_sql(sql).statements()
    assert raised.value.status == "UNSUPPORTED"
    assert sql.encode()[raised.value.start:raised.value.end].decode() == refused


def test_writes_map_query_expressions_and_returning(parse_sql: Callable[..., Translation]) -> None:
    """VALUES items, SET values and the WHERE expression are query expressions, and the
    write's `returning` field holds its RETURNING result columns as in SELECT (slice 3a;
    ADR 0013, D3)."""
    [insert, update] = [item.value for item in parse_sql(
        "INSERT INTO t VALUES (1 + 2) RETURNING *, a AS x; UPDATE t SET a = CAST(b AS INT) WHERE a < 1 RETURNING a;").statements()]
    write = insert["insert"]
    assert write["rows"] == [[{"arithmetic": {"operator": "add", "left": {"numeric": {"text": "1"}},
                                              "right": {"numeric": {"text": "2"}}}}]]
    assert write["returning"] == ["star", {"expression": {"value": column("a"), "alias": "x", "text": "a"}}]
    write = update["update"]
    assert write["assignments"] == [["a", {"cast": {"operand": column("b"), "typeName": "INT"}}]]
    assert write["filter"] == {"compare": {"operator": "lt", "left": column("a"), "right": {"numeric": {"text": "1"}}}}
    assert write["returning"] == [{"expression": {"value": column("a"), "alias": None, "text": "a"}}]


def test_delete_maps_filter_and_returning(parse_sql: Callable[..., Translation]) -> None:
    """`delete` (`Writes.lean`): DELETE keeps its table, its optional WHERE expression and its
    RETURNING result columns, empty without the clause, as for UPDATE (slice 3c)."""
    [plain, returned] = [item.value for item in parse_sql(
        "DELETE FROM t; DELETE FROM t WHERE a ISNULL RETURNING a;").statements()]
    assert plain == {"delete": {"table": "t", "filter": None, "returning": []}}
    assert returned == {"delete": {"table": "t", "filter": {"isNull": {"operand": column("a"), "negated": False}},
                                   "returning": [{"expression": {"value": column("a"), "alias": None, "text": "a"}}]}}


@pytest.mark.parametrize(("sql", "refused"), [
    ("WITH x AS (SELECT 1) DELETE FROM t;", "WITH x AS (SELECT 1)"),
    ("DELETE FROM t INDEXED BY i;", "INDEXED BY i"), ("DELETE FROM main.t;", "main.t"),
])
def test_delete_forms_outside_the_slice_are_refused(parse_sql: Callable[..., Translation], sql: str, refused: str) -> None:
    """`delete` refuses WITH, INDEXED BY and a schema-qualified table at their range."""
    with pytest.raises(SqlError) as raised:
        parse_sql(sql).statements()
    assert raised.value.status == "UNSUPPORTED"
    assert sql.encode()[raised.value.start:raised.value.end].decode() == refused


def test_joins_map_sources_kinds_and_conditions(parse_sql: Callable[..., Translation]) -> None:
    """`fromClause` (`Sources.lean`): the first table with its alias, then each join with its
    operator keywords as written, its table and its ON condition or USING names; `x.c` and
    `x.*` map to their constructors (slice 4)."""
    [query] = [item.value for item in parse_sql(
        "SELECT x.a, u.* FROM t AS x Left JOIN u ON x.a = u.a, v NATURAL join w CROSS JOIN y USING (b);").statements()]
    select = query["select"]
    assert select["source"] == {"table": "t", "alias": "x", "arguments": None, "query": None}
    assert select["columns"][0]["expression"]["value"] == {"qualified": {"source": "x", "column": "a"}}
    assert select["columns"][1] == {"sourceStar": {"source": "u"}}
    on = {"compare": {"operator": "eq", "left": {"qualified": {"source": "x", "column": "a"}},
                     "right": {"qualified": {"source": "u", "column": "a"}}}}
    assert select["joins"] == [
        {"operator": ["Left"], "source": {"table": "u", "alias": None, "arguments": None, "query": None}, "condition": on, "usingColumns": None},
        {"operator": [], "source": {"table": "v", "alias": None, "arguments": None, "query": None}, "condition": None, "usingColumns": None},
        {"operator": ["NATURAL"], "source": {"table": "w", "alias": None, "arguments": None, "query": None}, "condition": None, "usingColumns": None},
        {"operator": ["CROSS"], "source": {"table": "y", "alias": None, "arguments": None, "query": None}, "condition": None, "usingColumns": ["b"]}]


def test_table_valued_functions_map_with_their_arguments(parse_sql: Callable[..., Translation]) -> None:
    """`fromClause`: a table-valued function in FROM is a source with its name
    as written, its alias and its arguments as query expressions; a table has no arguments
    (ADR 0012, amendment 5, slice 6d)."""
    [query] = [item.value for item in parse_sql(
        "SELECT * FROM t, Json_Each(t.j, '$.a') AS e JOIN json_each('[1]') ON 1 = 1, json_each();").statements()]
    select = query["select"]
    assert select["source"] == {"table": "t", "alias": None, "arguments": None, "query": None}
    assert [join["source"] for join in select["joins"]] == [
        {"table": "Json_Each", "alias": "e", "query": None,
         "arguments": [{"qualified": {"source": "t", "column": "j"}}, {"string": {"bytes": list(b"$.a")}}]},
        {"table": "json_each", "alias": None, "query": None, "arguments": [{"string": {"bytes": list(b"[1]")}}]},
        {"table": "json_each", "alias": None, "query": None, "arguments": []}]
    assert select["joins"][1]["condition"] == {"compare": {"operator": "eq", "left": {"numeric": {"text": "1"}},
                                                          "right": {"numeric": {"text": "1"}}}}


def test_fallback_keywords_are_column_names(parse_sql: Callable[..., Translation]) -> None:
    """`expression` (`Expressions.lean`): a keyword that SQLite's grammar falls back to an
    identifier, such as `key`, names a column; the parse tree keeps the keyword's own
    symbol (`IDENTIFIER_TOKENS`, ADR 0012, amendment 5, slice 6d)."""
    [query] = [item.value for item in parse_sql("SELECT key, path, id, Replace FROM t WHERE key = 1;").statements()]
    select = query["select"]
    assert [column["expression"]["value"] for column in select["columns"]] == [
        column("key"), column("path"), column("id"), column("Replace")]
    assert select["filter"] == {"compare": {"operator": "eq", "left": column("key"),
                                            "right": {"numeric": {"text": "1"}}}}


def test_select_without_from_has_no_source(parse_sql: Callable[..., Translation]) -> None:
    """`statement` (`Statements.lean`): a SELECT without FROM has a null source and no joins, and
    keeps its other clauses (ADR 0012, amendment 5, slice 6a)."""
    [statement] = [item.value for item in parse_sql("SELECT 1 WHERE 1 = 1 LIMIT 2;").statements()]
    select = statement["select"]
    assert select["source"] is None and select["joins"] == []
    assert select["filter"] == {"compare": {"operator": "eq", "left": {"numeric": {"text": "1"}},
                                            "right": {"numeric": {"text": "1"}}}}
    assert select["limit"] == {"numeric": {"text": "2"}}


def test_having_and_distinct_map_only_when_written(parse_sql: Callable[..., Translation]) -> None:
    """`queryClauses` (`Select.lean`): `HAVING` maps to `having` and `SELECT DISTINCT` to
    `distinct` (ADR 0018, D3); a statement without them has neither field, so its JSON keeps the
    form of frozen records, and `ALL` is no `DISTINCT`."""
    [grouped, plain, every] = [item.value for item in parse_sql(
        "SELECT DISTINCT a FROM t GROUP BY a HAVING count(*) > 1; SELECT a FROM t; SELECT ALL a FROM t;").statements()]
    assert grouped["select"]["distinct"] is True
    assert grouped["select"]["having"] == {"compare": {"operator": "gt", "left": {"callStar": {"name": "count"}},
                                                       "right": {"numeric": {"text": "1"}}}}
    assert "having" not in plain["select"] and "distinct" not in plain["select"]
    assert "distinct" not in every["select"]
