"""The frontend maps function calls to statement syntax (`belay.sqlite.syntax_queries`).

These tests check the JSON that Lean's `Syntax.Expr` decoder reads for calls without
arguments, with one argument and with several, and for the JSON operators, which SQLite's
parser makes calls (ADR 0012, slices 2, 6b and 6f).
"""

from collections.abc import Callable

import pytest

from belay.sqlite.sql_tree import Tree
from belay.sqlite.syntax import statements

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


def column(name: str) -> dict[str, object]:
    """The JSON of an identifier written without double quotes."""
    return {"identifier": {"name": name, "doubleQuoted": False}}


def test_call_without_arguments_maps_to_call_empty(parse_sql: Callable[..., Tree]) -> None:
    """A call without arguments, such as `date()` or `random()`, is a `callEmpty` with its name
    as written (ADR 0012, slice 6f); resolution decides whether the model has the function."""
    [select] = [item.value for item in statements(parse_sql("SELECT Date(), random();"))]
    assert [column["expression"]["value"] for column in select["select"]["columns"]] == [
        {"callEmpty": {"name": "Date"}}, {"callEmpty": {"name": "random"}}]


def test_numbers_map_arithmetic_cast_and_call_chains(parse_sql: Callable[..., Tree]) -> None:
    """Arithmetic, unary minus of an expression, CAST with its type name as written, and a
    call with three arguments as a `callPair` whose arguments after the second are a `more`
    node (ADR 0012, slices 2 and 6b)."""
    [select] = [item.value for item in statements(parse_sql(
        "SELECT -(a % 2) * b, CAST(a AS Varchar(10)), Coalesce(a, b, 3) FROM t;"))]
    values = [column["expression"]["value"] for column in select["select"]["columns"]]
    remainder = {"arithmetic": {"operator": "remainder", "left": column("a"), "right": {"numeric": {"text": "2"}}}}
    assert values[0] == {"arithmetic": {"operator": "multiply", "left": {"negate": {"operand": remainder}},
                                        "right": column("b")}}
    assert values[1] == {"cast": {"operand": column("a"), "typeName": "Varchar(10)"}}
    assert values[2] == {"callPair": {"name": "Coalesce", "first": column("a"), "rest": {
        "more": {"first": column("b"), "rest": {"numeric": {"text": "3"}}}}}}


def test_json_operators_and_nested_calls_map_to_call_pairs(parse_sql: Callable[..., Tree]) -> None:
    """`->` and `->>` are a `callPair` of the function with the operator's text as its name, and
    a nested call of two arguments stays a `callPair`, distinct from a `more` node of three
    arguments (`syntax_queries.query_expression`, `argument_rest`; ADR 0012, slice 6b)."""
    [select] = [item.value for item in statements(parse_sql(
        "SELECT a -> '$.x', a ->> 'y', json_extract(a, json_extract(b, c)), json_extract(a, b, c) FROM t;"))]
    values = [column["expression"]["value"] for column in select["select"]["columns"]]
    assert values[0] == {"callPair": {"name": "->", "first": column("a"), "rest": {"string": {"bytes": list(b"$.x")}}}}
    assert values[1] == {"callPair": {"name": "->>", "first": column("a"), "rest": {"string": {"bytes": list(b"y")}}}}
    assert values[2] == {"callPair": {"name": "json_extract", "first": column("a"), "rest": {
        "callPair": {"name": "json_extract", "first": column("b"), "rest": column("c")}}}}
    assert values[3] == {"callPair": {"name": "json_extract", "first": column("a"), "rest": {
        "more": {"first": column("b"), "rest": column("c")}}}}
