"""The SET lists of UPDATE and DO UPDATE, the ON CONFLICT clauses of INSERT, and the
conflict algorithms of `INSERT OR algorithm`, `REPLACE INTO` and of constraints.

SQLite's grammar gives the clauses of an INSERT as a right-nested `upsert` node whose
last part is the next clause, or the RETURNING clause. A clause maps to the Lean
structure `Syntax.ConflictClause`: its target (column names, or none) and its action
(`nothing`, or `update` with assignments and an optional filter). A target is a list of
plain column names; a direction, `NULLS FIRST` or `NULLS LAST`, a collation or another
expression in a target, and the WHERE clause of a target, are refused with their source
range.
"""

from .located import Located, constructor, leaf, pair, sequence, structure
from .sql_tree import Node, Tree
from .syntax_definitions import absent, left_list, require, resolve_type
from .syntax_expressions import name
from .syntax_queries import query_expression


def assignment_list(tree: Tree, assignments: Node) -> Located:
    """Map a `setlist` node to its `column = expression` pairs in source order."""
    items = [pair(name(tree, item[-3]), query_expression(tree, item[-1]), item[-3].start, item[-1].end)
             for item in left_list(tree, assignments, {3: ["nm", "EQ", "expr"],
                                                       5: ["setlist", "COMMA", "nm", "EQ", "expr"]})]
    return sequence(items, assignments.start, assignments.end)


def target_column(tree: Tree, item: list[Node]) -> Located:
    """One column of a conflict target: `expr sortorder nulls` where the expression is a
    plain name and the order parts are empty."""
    expression, order, nulls = item[-3:]
    absent(tree, order, "A direction in an ON CONFLICT target")
    absent(tree, nulls, "NULLS FIRST or NULLS LAST in an ON CONFLICT target")
    located = query_expression(tree, expression)
    if not (isinstance(located.value, dict) and "identifier" in located.value):
        raise tree.unsupported(expression, "Only column names are modeled in an ON CONFLICT target; "
                                           "write the column names")
    return located.children[0]


def conflict_target(tree: Tree, columns: Node, condition: Node) -> Located:
    """Map the target `(sortlist) where_opt` of a clause to its column names."""
    absent(tree, condition, "A WHERE clause of an ON CONFLICT target")
    items = [target_column(tree, item) for item in left_list(tree, columns, {
        3: ["expr", "sortorder", "nulls"], 5: ["sortlist", "COMMA", "expr", "sortorder", "nulls"]})]
    return sequence(items, columns.start, columns.end)


def update_action(tree: Tree, assignments: Node, condition: Node, start: int, end: int) -> Located:
    """Map `DO UPDATE SET setlist where_opt` to the `update` action."""
    parts = tree.children(condition)
    filter_ = query_expression(tree, parts[1]) if parts else leaf(None, condition.start, condition.end)
    return constructor("update", [("assignments", assignment_list(tree, assignments)), ("filter", filter_)],
                       start, end)


def conflict_clauses(tree: Tree, upsert: Node) -> tuple[Located, list[Node]]:
    """The ON CONFLICT clauses of an `upsert` node in written order, and the parts
    `RETURNING selcollist`, empty without RETURNING."""
    clauses: list[Located] = []
    current = upsert
    while True:
        parts = tree.children(current)
        symbols = [part.symbol for part in parts]
        if symbols in ([], ["RETURNING", "selcollist"]):
            return sequence(clauses, upsert.start, upsert.end), parts
        if symbols == ["ON", "CONFLICT", "LP", "sortlist", "RP", "where_opt", "DO", "NOTHING", "upsert"]:
            target, action = conflict_target(tree, parts[3], parts[5]), leaf("nothing", parts[6].start, parts[7].end)
        elif symbols == ["ON", "CONFLICT", "LP", "sortlist", "RP", "where_opt", "DO", "UPDATE", "SET", "setlist",
                         "where_opt", "upsert"]:
            target = conflict_target(tree, parts[3], parts[5])
            action = update_action(tree, parts[9], parts[10], parts[6].start, parts[10].end)
        elif symbols == ["ON", "CONFLICT", "DO", "NOTHING", "returning"]:
            target, action = leaf(None, parts[1].end, parts[1].end), leaf("nothing", parts[2].start, parts[3].end)
        else:
            require(tree, current, ["ON", "CONFLICT", "DO", "UPDATE", "SET", "setlist", "where_opt", "returning"])
            target = leaf(None, parts[1].end, parts[1].end)
            action = update_action(tree, parts[5], parts[6], parts[2].start, parts[6].end)
        clauses.append(structure([("target", target), ("action", action)], parts[0].start, parts[-2].end))
        current = parts[-1]


def insert_algorithm(tree: Tree, operation: Node) -> Located:
    """The algorithm of an `insert_cmd` node: `REPLACE` for `REPLACE INTO`, the algorithm of
    `INSERT OR algorithm`, or none for a plain `INSERT`."""
    parts = tree.children(operation)
    if [part.symbol for part in parts] == ["REPLACE"]:
        return leaf("replace", operation.start, operation.end)
    _, conflict = require(tree, operation, ["INSERT", "orconf"])
    if not conflict.children:
        return leaf(None, conflict.start, conflict.end)
    _, kind = require(tree, conflict, ["OR", "resolvetype"])
    return resolve_type(tree, kind)
