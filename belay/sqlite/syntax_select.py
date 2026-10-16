"""Map a SELECT to statement syntax (ADR 0012, slice 1, and amendment 2 for joins).

A query keeps its result columns, its first table and its joins (`syntax_sources`), or
none for a SELECT without FROM (ADR 0012, amendment 5, slice 6a), and its WHERE, GROUP BY,
ORDER BY, LIMIT and OFFSET clauses. Compound SELECT, WITH, DISTINCT, HAVING and NULLS
FIRST or LAST have no constructor and are refused with their source range.
"""

from .located import Located, constructor, leaf, sequence, structure
from .sql_tree import Node, Tree
from .syntax_definitions import absent, left_list, require
from .syntax_queries import query_expression, result_columns
from .syntax_sources import from_clause


def order_terms(tree: Tree, node: Node) -> list[Located]:
    """Map the ORDER BY terms in source order, with their direction."""
    terms: list[Located] = []
    for item in left_list(tree, node, {3: ["expr", "sortorder", "nulls"],
                                       5: ["sortlist", "COMMA", "expr", "sortorder", "nulls"]}):
        term, direction, nulls = item[-3:]
        absent(tree, nulls, "NULLS FIRST or NULLS LAST")
        descending = [child.symbol for child in tree.children(direction)] == ["DESC"]
        terms.append(structure([("expression", query_expression(tree, term)),
                                ("descending", leaf(descending, direction.start, direction.end))],
                               term.start, max(term.end, direction.end)))
    return terms


def optional(located: Located | None, node: Node) -> Located:
    """An optional part: the located value, or a null leaf at the clause."""
    return located if located is not None else leaf(None, node.start, node.end)


def select(tree: Tree, command: Node) -> Located:
    """Map `SELECT ... [FROM tables] [WHERE] [GROUP BY] [ORDER BY] [LIMIT [OFFSET]]`; without
    FROM, the source is a null leaf and the joins are empty."""
    (current,) = require(tree, command, ["select"])
    (current,) = require(tree, current, ["selectnowith"])
    (one,) = require(tree, current, ["oneselect"])
    _, distinct, columns, source, where, group, having, order, limit = require(tree, one, [
        "SELECT", "distinct", "selcollist", "from", "where_opt", "groupby_opt", "having_opt", "orderby_opt", "limit_opt"])
    absent(tree, distinct, "DISTINCT or ALL")
    absent(tree, having, "HAVING")
    if source.children:
        _, tables = require(tree, source, ["FROM", "seltablist"])
        first_table, joins = from_clause(tree, tables, query_expression)
    else:
        first_table, joins = leaf(None, source.start, source.end), sequence([], source.start, source.end)
    condition = query_expression(tree, tree.children(where)[1]) if where.children else None
    grouping = [query_expression(tree, item[-1]) for item in left_list(
        tree, tree.children(group)[2], {1: ["expr"], 3: ["nexprlist", "COMMA", "expr"]})] if group.children else []
    ordering = order_terms(tree, tree.children(order)[2]) if order.children else []
    bounds = tree.children(limit)
    window = [child.symbol for child in bounds]
    count = offset = None
    if window == ["LIMIT", "expr"]:
        count = query_expression(tree, bounds[1])
    elif window in (["LIMIT", "expr", "OFFSET", "expr"], ["LIMIT", "expr", "COMMA", "expr"]):
        first, second = query_expression(tree, bounds[1]), query_expression(tree, bounds[3])
        count, offset = (first, second) if window[2] == "OFFSET" else (second, first)
    elif window:
        raise tree.unsupported(limit, "Unsupported LIMIT form; write LIMIT n [OFFSET m]")
    return constructor("select", [
        ("columns", result_columns(tree, columns)), ("source", first_table), ("joins", joins),
        ("filter", optional(condition, where)), ("groupBy", sequence(grouping, group.start, group.end)),
        ("orderBy", sequence(ordering, order.start, order.end)), ("limit", optional(count, limit)),
        ("offset", optional(offset, limit))], command.start, command.end)
