"""The ON CONFLICT clauses and the conflict algorithm of INSERT in `belay.sqlite.syntax_conflicts`.

These tests check the JSON that Lean's `Syntax.ConflictClause` decoder reads: the
target column names as written, or none, and the action, `nothing` or `update` with its
assignments and optional filter; the clauses in written order; and an INSERT without
clauses with an empty list. They also check that the target forms the model does not
decide are refused at their source range.
"""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from belay.sqlite.sql_tree import Tree
from belay.sqlite.syntax import statements

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]

NAME = {"identifier": {"name": "b", "doubleQuoted": False}}
"""The unqualified name `b`."""


def insert_of(parse_sql: Callable[..., Tree], sql: str) -> dict[str, object]:
    """The fields of the INSERT of one statement, inside a RETURNING wrapper or not."""
    [statement] = [item.value for item in statements(parse_sql(sql))]
    assert isinstance(statement, dict)
    if "returning" in statement:
        statement = statement["returning"]["write"]
    return statement["insert"]


def test_insert_without_clauses_has_no_conflicts(parse_sql: Callable[..., Tree]) -> None:
    """An INSERT without ON CONFLICT has an empty clause list."""
    assert insert_of(parse_sql, "INSERT INTO t VALUES (1);")["conflicts"] == []


def test_clauses_keep_targets_actions_and_order(parse_sql: Callable[..., Tree]) -> None:
    """Each clause keeps its target names as written and its action; the clauses keep their
    written order before RETURNING."""
    sql = ("INSERT INTO t(a, b) VALUES (1, 2) ON CONFLICT(b, A) DO UPDATE SET a = excluded.a WHERE b > 0 "
           "ON CONFLICT DO NOTHING RETURNING a;")
    excluded = {"qualified": {"source": "excluded", "column": "a"}}
    assert insert_of(parse_sql, sql)["conflicts"] == [
        {"target": ["b", "A"], "action": {"update": {"assignments": [["a", excluded]], "filter": {
            "compare": {"operator": "gt", "left": NAME, "right": {"numeric": {"text": "0"}}}}}}},
        {"target": None, "action": "nothing"}]


def test_update_without_target_or_filter(parse_sql: Callable[..., Tree]) -> None:
    """DO UPDATE without target and without WHERE has no target and no filter."""
    sql = "INSERT INTO t VALUES (1) ON CONFLICT DO UPDATE SET b = b;"
    assert insert_of(parse_sql, sql)["conflicts"] == [
        {"target": None, "action": {"update": {"assignments": [["b", NAME]], "filter": None}}}]


@pytest.mark.parametrize(("clause", "refused"), [
    ("ON CONFLICT(a DESC) DO NOTHING", "DESC"),
    ("ON CONFLICT(a NULLS LAST) DO NOTHING", "NULLS LAST"),
    ("ON CONFLICT(a COLLATE nocase) DO NOTHING", "a COLLATE nocase"),
    ("ON CONFLICT(t.a) DO NOTHING", "t.a"),
    ("ON CONFLICT(a) WHERE a > 0 DO NOTHING", "WHERE a > 0"),
])
def test_target_forms_are_refused_at_their_range(parse_sql: Callable[..., Tree], clause: str, refused: str) -> None:
    """A direction, a NULLS order, a collation, a qualified name and the WHERE clause of a
    target are refused, and the error range is the refused text."""
    sql = f"INSERT INTO t VALUES (1) {clause};"
    with pytest.raises(SqlError) as raised:
        statements(parse_sql(sql))
    assert sql.encode()[raised.value.start:raised.value.end].decode() == refused


@pytest.mark.parametrize(("sql", "algorithm"), [
    ("INSERT INTO t VALUES (1);", None), ("INSERT OR ROLLBACK INTO t VALUES (1);", "rollback"),
    ("INSERT OR ABORT INTO t VALUES (1);", "abort"), ("INSERT OR FAIL INTO t VALUES (1);", "fail"),
    ("INSERT OR IGNORE INTO t VALUES (1);", "ignore"), ("INSERT OR REPLACE INTO t VALUES (1);", "replace"),
    ("REPLACE INTO t VALUES (1);", "replace"),
    ("INSERT OR IGNORE INTO t VALUES (1) ON CONFLICT DO NOTHING RETURNING 1;", "ignore"),
])
def test_insert_keeps_its_algorithm(parse_sql: Callable[..., Tree], sql: str, algorithm: str | None) -> None:
    """`INSERT OR algorithm` and `REPLACE INTO` give the Lean `ConflictAlgorithm` constructor
    name; a plain INSERT has none."""
    assert insert_of(parse_sql, sql)["algorithm"] == algorithm
