"""The translation lifts the subqueries of a statement into its list (`packages/belay-sqlite-text/Belay/Sqlite/Translation/Subqueries.lean`,
through the text package's program).

These tests check the JSON that Lean's `Syntax.Subquery` decoder reads: the forms that name
a subquery by its index, the order of the list and the query around each subquery, the
subqueries of writes, and the refusal of a subquery where the model does not place it (ADR 0018,
D1). `tests/surface/TranslationChecks.lean` checks the source range of a subquery's clauses.
"""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from conformance.sql_text import Translation

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


def column(name: str) -> dict[str, object]:
    """The JSON of an identifier written without double quotes."""
    return {"identifier": {"name": name, "quote": "none"}}


def test_forms_name_subqueries_in_text_order(parse_sql: Callable[..., Translation]) -> None:
    """EXISTS, NOT IN and a scalar subquery name the subqueries 0, 1 and 2 in the order of their
    text; NOT EXISTS is NOT of EXISTS, and each subquery keeps its clauses."""
    [statement] = [item.value for item in parse_sql(
        "SELECT (SELECT max(b) FROM u) FROM t WHERE NOT EXISTS (SELECT 1 FROM u WHERE u.b = t.a) "
        "AND a NOT IN (SELECT b FROM u);").statements()]
    select = statement["select"]
    assert select["columns"][0]["expression"]["value"] == {"subquery": {"index": 0}}
    assert select["filter"] == {"and": {
        "left": {"not": {"operand": {"exists": {"index": 1}}}},
        "right": {"inQuery": {"operand": column("a"), "index": 2, "negated": True}}}}
    first, second, third = select["subqueries"]
    assert first["columns"] == [{"expression": {"value": {"call": {"name": "max", "arguments": [column("b")]}},
                                                "alias": None, "text": "max(b)"}}]
    assert second["filter"] == {"compare": {"operator": "eq", "left": {"qualified": {"source": "u", "column": "b"}},
                                            "right": {"qualified": {"source": "t", "column": "a"}}}}
    assert third["source"] == {"table": "u", "alias": None, "arguments": None, "query": None}
    assert [item["parent"] for item in (first, second, third)] == [None, None, None]


def test_nested_subqueries_name_the_query_around_them(parse_sql: Callable[..., Translation]) -> None:
    """A subquery inside a subquery comes after it and names it as its parent; a later
    subquery of the statement's query comes after both."""
    [statement] = [item.value for item in parse_sql(
        "SELECT 1 FROM t WHERE EXISTS (SELECT 1 FROM u WHERE b IN (SELECT a FROM t)) AND EXISTS (SELECT 2);").statements()]
    subqueries = statement["select"]["subqueries"]
    assert [item["parent"] for item in subqueries] == [None, 0, None]
    assert subqueries[0]["filter"] == {"inQuery": {"operand": column("b"), "index": 1, "negated": False}}
    assert subqueries[2]["source"] is None


def test_writes_list_the_subqueries_of_their_expressions(parse_sql: Callable[..., Translation]) -> None:
    """INSERT VALUES, UPDATE SET and WHERE, and DELETE WHERE list their subqueries in the
    `subqueries` field, with the write as the query around them; a statement without subqueries
    has no such field, so its JSON keeps the form of frozen records. The model's transport writes
    an object's fields in sorted order."""
    [insert, update, delete] = [item.value for item in parse_sql(
        "INSERT INTO t VALUES ((SELECT max(b) FROM u)); UPDATE t SET a = (SELECT 1) WHERE EXISTS (SELECT 2); "
        "DELETE FROM t WHERE a IN (SELECT b FROM u);").statements()]
    assert insert["insert"]["rows"] == [[{"subquery": {"index": 0}}]]
    assert [item["parent"] for item in insert["insert"]["subqueries"]] == [None]
    assert update["update"]["assignments"] == [["a", {"subquery": {"index": 0}}]]
    assert update["update"]["filter"] == {"exists": {"index": 1}}
    assert len(update["update"]["subqueries"]) == 2
    assert delete["delete"]["filter"] == {"inQuery": {"operand": column("a"), "index": 0, "negated": False}}
    assert sorted(delete["delete"]) == ["filter", "returning", "subqueries", "table"]
    [plain] = [item.value for item in parse_sql("DELETE FROM t;").statements()]
    assert "subqueries" not in plain["delete"]


@pytest.mark.parametrize(("sql", "refused"), [
    ("UPDATE t SET a = 1 RETURNING (SELECT 1);", "SELECT 1"),
    ("INSERT INTO t VALUES (1) ON CONFLICT DO UPDATE SET a = (SELECT 1);", "SELECT 1"),
    ("CREATE TABLE c(a CHECK (a IN (SELECT 1)));", "SELECT 1"),
    ("SELECT a FROM t WHERE a IN u;", "a IN u"),
])
def test_subqueries_outside_their_clauses_are_refused(parse_sql: Callable[..., Translation], sql: str, refused: str) -> None:
    """A subquery in RETURNING, ON CONFLICT or a schema statement, and `x IN table`, have no
    constructor and are refused at their range."""
    with pytest.raises(SqlError) as raised:
        parse_sql(sql).statements()
    assert raised.value.status == "UNSUPPORTED"
    assert sql.encode()[raised.value.start:raised.value.end].decode() == refused


def test_derived_sources_share_the_indexed_query_list(parse_sql: Callable[..., Translation]) -> None:
    """Sources.lean lifts FROM SELECTs through the expression-subquery index and parent machinery.
    SQL order of joins is preserved even though the source-list walker allocates from the right."""
    [statement] = [item.value for item in parse_sql(
        "SELECT (SELECT d.x) FROM (SELECT 1 AS x) d JOIN (SELECT (SELECT 2) AS y) e ON d.x = e.y;"
    ).statements()]
    select = statement["select"]
    queries = select["subqueries"]
    first = select["source"]
    second = select["joins"][0]["source"]
    assert first["table"] == second["table"] == ""
    assert (first["alias"], second["alias"]) == ("d", "e")
    assert first["arguments"] is second["arguments"] is None
    assert queries[first["query"]]["columns"][0]["expression"]["alias"] == "x"
    nested = queries[second["query"]]["columns"][0]["expression"]["value"]["subquery"]["index"]
    assert queries[nested]["parent"] == second["query"]
    assert queries[first["query"]]["parent"] is queries[second["query"]]["parent"] is None


def test_derived_source_parameter_numbers_remain_textual(parse_sql: Callable[..., Translation]) -> None:
    """Derived SELECT translation reuses parser parameter numbers despite the source walk order."""
    [statement] = [item.value for item in parse_sql(
        "SELECT ? FROM (SELECT ? AS x) d JOIN (SELECT ? AS y) e ON d.x = e.y;"
    ).statements()]
    select = statement["select"]
    queries = select["subqueries"]
    sources = [select["source"], select["joins"][0]["source"]]
    values = [select["columns"][0]["expression"]["value"]] + [
        queries[source["query"]]["columns"][0]["expression"]["value"] for source in sources]
    assert values == [{"parameter": {"number": index}} for index in (1, 2, 3)]
