"""Map the FROM clause of a SELECT to its first table and its joins (ADR 0012, amendment 2).

A table reference is a table name with an optional alias. Each join after the first
table has the keywords of its operator as written, its table, and its optional ON
condition and USING column names. Lean reads the kind of the join from the keywords
and decides which joins the model describes, so this module does not fold their case. A
table-valued function such as `json_each(json, path)` is a reference with its arguments
(ADR 0012, amendment 5, slice 6d); Lean decides which functions the model describes.
Schema names, INDEXED BY and subqueries in FROM have no constructor and are refused with
their source range.
"""

from collections.abc import Callable

from .located import Located, constructor, leaf, sequence, structure
from .sql_tree import Node, Tree
from .syntax_definitions import absent, left_list, require
from .syntax_expressions import dequote, name

def alias(tree: Tree, node: Node) -> Located:
    """The alias of an `as` node: `AS name`, a bare name, or none."""
    parts = tree.children(node)
    if [part.symbol for part in parts] == ["AS", "nm"]:
        return name(tree, parts[1])
    if parts:
        return leaf(dequote(tree.text(parts[0])), node.start, node.end)
    return leaf(None, node.start, node.end)


def table_reference(tree: Tree, table: Node, schema: Node, alias_node: Node, arguments: Located | None) -> Located:
    """A table name, or a table-valued function name with its arguments, with its optional
    alias; a schema name is refused. `arguments` is none for a table."""
    absent(tree, schema, "A schema name")
    return structure([("table", name(tree, table)), ("alias", alias(tree, alias_node)),
                      ("arguments", arguments if arguments is not None else leaf(None, table.start, table.end))],
                     table.start, max(table.end, alias_node.end))


TABLE = ["stl_prefix", "nm", "dbnm", "as", "on_using"]
"""The parts of a table in FROM."""
FUNCTION = ["stl_prefix", "nm", "dbnm", "LP", "exprlist", "RP", "as", "on_using"]
"""The parts of a table-valued function in FROM."""


def source_parts(tree: Tree, node: Node, condition: Callable[[Tree, Node], Located]) -> tuple[Node, Node, Node, Node,
                                                                                               Node, Located | None]:
    """The prefix, name, schema, alias and constraint of one source of a `seltablist`, and
    the mapped arguments of a table-valued function, or none for a table. A subquery or
    INDEXED BY is refused."""
    parts = tree.children(node)
    symbols = [part.symbol for part in parts]
    if symbols == TABLE:
        prefix, table, schema, alias_node, constraint = parts
        return prefix, table, schema, alias_node, constraint, None
    if symbols == FUNCTION:
        prefix, table, schema, _, listed, closing, alias_node, constraint = parts
        items = left_list(tree, tree.children(listed)[0], {1: ["expr"], 3: ["nexprlist", "COMMA", "expr"]}) \
            if listed.children else []
        return prefix, table, schema, alias_node, constraint, sequence(
            [condition(tree, item[-1]) for item in items], listed.start, closing.start)
    raise tree.unsupported(node, "Only tables and table-valued functions, with optional aliases, are modeled in "
                           "FROM; write table names and joins")


def join_operator(tree: Tree, node: Node) -> Located:
    """The keywords of a `joinop` before `JOIN`, as written; none for `,` and a plain `JOIN`."""
    words = [leaf(tree.text(part), part.start, part.end) for part in tree.children(node)
             if part.symbol not in ("COMMA", "JOIN")]
    return sequence(words, node.start, node.end)


def join_constraint(tree: Tree, node: Node, condition: Callable[[Tree, Node], Located]) -> tuple[Located, Located]:
    """The ON condition and the USING column names of an `on_using` node, each a null
    leaf when absent."""
    parts = tree.children(node)
    symbols = [part.symbol for part in parts]
    missing = leaf(None, node.start, node.end)
    if symbols == ["ON", "expr"]:
        return condition(tree, parts[1]), missing
    if symbols == ["USING", "LP", "idlist", "RP"]:
        names = [name(tree, item[-1]) for item in left_list(tree, parts[2], {1: ["nm"], 3: ["idlist", "COMMA", "nm"]})]
        return missing, sequence(names, parts[2].start, parts[2].end)
    return missing, missing


def from_clause(tree: Tree, tables: Node,
                condition: Callable[[Tree, Node], Located]) -> tuple[Located, Located]:
    """The first source of a `seltablist` and its joins in order; `condition` maps an ON
    expression and the arguments of a table-valued function. A subquery is refused."""
    items: list[tuple[Node, tuple[Node, Node, Node, Node, Node, Located | None]]] = []
    current = tables
    while True:
        parts = source_parts(tree, current, condition)
        items.append((current, parts))
        if not tree.children(parts[0]):
            break
        current = require(tree, parts[0], ["seltablist", "joinop"])[0]
    items.reverse()
    first_node, (_, table, schema, alias_node, constraint, arguments) = items[0]
    absent(tree, constraint, "ON or USING on the first table")
    first = table_reference(tree, table, schema, alias_node, arguments)
    joins: list[Located] = []
    for node, (prefix, table, schema, alias_node, constraint, arguments) in items[1:]:
        operator = require(tree, prefix, ["seltablist", "joinop"])[1]
        on, using = join_constraint(tree, constraint, condition)
        joins.append(structure([
            ("operator", join_operator(tree, operator)),
            ("source", table_reference(tree, table, schema, alias_node, arguments)),
            ("condition", on),
            ("usingColumns", using)], operator.start, node.end))
    return first, sequence(joins, first_node.end, tables.end)
