"""The translation maps a compound SELECT (`packages/belay-sqlite-text/Belay/Sqlite/Translation/CompoundSelect.lean`,
through the text package's program; ADR 0019, D3).

These tests check the JSON that Lean's `Syntax.Statement.select` and `Syntax.Subquery` decoders
read for a compound: each operator, the terms as subqueries whose parent is the compound's query,
the compound's ORDER BY and LIMIT, which the parser puts on the last term, and the refusals: the
errors of SQLite's parser actions as `INPUT_ERROR` with SQLite's message, and the forms that the
model does not place. `tests/surface/TranslationChecks.lean` checks the ranges of a compound's
paths.
"""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from conformance.sql_text import Translation

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


def literal(text: str) -> dict[str, object]:
    """The JSON of a numeric literal."""
    return {"numeric": {"text": text}}


@pytest.mark.parametrize(("keywords", "operator"), [
    ("UNION ALL", "unionAll"), ("UNION", "union"), ("INTERSECT", "intersect"), ("EXCEPT", "except"),
])
def test_each_operator_names_its_terms(parse_sql: Callable[..., Translation], keywords: str, operator: str) -> None:
    """A compound statement has no clauses of its own but ORDER BY and LIMIT; its terms are the
    statement's subqueries 0 and 1 without a parent, and the last term has no ORDER BY or LIMIT."""
    [statement] = [item.value for item in parse_sql(
        f"SELECT 1 AS a {keywords} SELECT b FROM t WHERE b > 0 ORDER BY 1 DESC LIMIT 2 OFFSET 1;").statements()]
    select = statement["select"]
    assert select["compound"] == {"first": 0, "rest": [[operator, 1]]}
    assert (select["columns"], select["source"], select["filter"]) == ([], None, None)
    assert select["orderBy"] == [{"expression": literal("1"), "descending": True}]
    assert (select["limit"], select["offset"]) == (literal("2"), literal("1"))
    first, second = select["subqueries"]
    assert [first["parent"], second["parent"]] == [None, None]
    assert second["source"] == {"table": "t", "alias": None, "arguments": None, "query": None}
    assert (second["orderBy"], second["limit"], second["offset"]) == ([], None, None)
    assert first["compound"] is None and second["compound"] is None


def test_operators_keep_text_order(parse_sql: Callable[..., Translation]) -> None:
    """A chain lists its operators from left to right, each with the term on its right; a
    statement without a compound has no `compound` field, so its JSON keeps its form."""
    [chain, single] = [item.value for item in parse_sql(
        "SELECT 1 UNION SELECT 2 INTERSECT SELECT 3 EXCEPT SELECT 4 UNION ALL SELECT 5; SELECT 1;").statements()]
    assert chain["select"]["compound"] == {"first": 0, "rest": [["union", 1], ["intersect", 2], ["except", 3],
                                                                ["unionAll", 4]]}
    assert "compound" not in single["select"]


def test_compound_subquery_lists_its_terms_after_it(parse_sql: Callable[..., Translation]) -> None:
    """A compound subquery comes first, then each term with the compound as its parent, each
    before its own subqueries; the compound subquery has the ORDER BY of the compound."""
    [statement] = [item.value for item in parse_sql(
        "SELECT 1 IN (SELECT a FROM t WHERE EXISTS (SELECT 1) UNION SELECT 2 ORDER BY 1) FROM t;").statements()]
    select = statement["select"]
    assert select["columns"][0]["expression"]["value"]["inQuery"]["index"] == 0
    wrapper, first, nested, second = select["subqueries"]
    assert wrapper["compound"] == {"first": 1, "rest": [["union", 3]]}
    assert wrapper["orderBy"] == [{"expression": literal("1"), "descending": False}]
    assert [item["parent"] for item in (wrapper, first, nested, second)] == [None, 0, 1, 0]
    assert first["filter"] == {"exists": {"index": 2}}


@pytest.mark.parametrize(("sql", "message", "at"), [
    ("SELECT 1 ORDER BY 1 UNION SELECT 2;", "ORDER BY clause should come after UNION not before", "ORDER BY 1"),
    ("SELECT 1 LIMIT 1 EXCEPT SELECT 2 INTERSECT SELECT 3;", "LIMIT clause should come after EXCEPT not before",
     "LIMIT 1"),
    ("SELECT 1 LIMIT 1 UNION SELECT 2 ORDER BY 1 UNION ALL SELECT 3;",
     "ORDER BY clause should come after UNION ALL not before", "ORDER BY 1"),
])
def test_clause_before_the_last_term_is_sqlites_parser_error(
        parse_sql: Callable[..., Translation], sql: str, message: str, at: str) -> None:
    """`compoundParseError`: the right-most term before the last with ORDER BY or LIMIT gives
    SQLite's message with the operator on its right, at the range of the clause."""
    with pytest.raises(SqlError) as raised:
        parse_sql(sql).statements()
    assert raised.value.status == "INPUT_ERROR"
    assert message in str(raised.value)
    assert sql.encode()[raised.value.start:raised.value.end].decode().strip() == at


def test_term_limit_is_sqlites_compound_limit(parse_sql: Callable[..., Translation]) -> None:
    """500 terms map; 501 terms are SQLite's `too many terms in compound SELECT`, which also
    replaces the ORDER BY error when the walk from the right counts more than 500 terms."""
    [statement] = [item.value for item in parse_sql("SELECT 1" + " UNION SELECT 1" * 499 + ";").statements()]
    assert len(statement["select"]["subqueries"]) == 500
    for sql in ["SELECT 1" + " UNION SELECT 1" * 500 + ";", "SELECT 1 ORDER BY 1" + " UNION SELECT 1" * 500 + ";"]:
        with pytest.raises(SqlError) as raised:
            parse_sql(sql).statements()
        assert raised.value.status == "INPUT_ERROR"
        assert "too many terms in compound SELECT" in str(raised.value)
    with pytest.raises(SqlError) as raised:
        parse_sql("SELECT 1" + " UNION SELECT 1" * 400 + " UNION SELECT 1 LIMIT 1" + " UNION SELECT 1" * 100 + ";").statements()
    assert "LIMIT clause should come after UNION not before" in str(raised.value)


@pytest.mark.parametrize(("sql", "refused"), [
    ("SELECT 1 UNION SELECT 2 ORDER BY (SELECT 1);", "SELECT 1"),
    ("SELECT 1 UNION VALUES (2);", "VALUES (2)"),
    ("CREATE TRIGGER r AFTER INSERT ON t BEGIN SELECT 1 UNION SELECT 2; END;", "SELECT 1 UNION SELECT 2"),
    ("INSERT INTO t SELECT 1 UNION SELECT 2;", "SELECT 1 UNION SELECT 2"),
])
def test_compound_forms_outside_the_slice_are_unsupported(
        parse_sql: Callable[..., Translation], sql: str, refused: str) -> None:
    """A subquery in the compound's ORDER BY or LIMIT, a VALUES term, a compound statement in a
    trigger body and a compound INSERT source are UNSUPPORTED at their range."""
    with pytest.raises(SqlError) as raised:
        parse_sql(sql).statements()
    assert raised.value.status == "UNSUPPORTED"
    assert sql.encode()[raised.value.start:raised.value.end].decode() == refused
