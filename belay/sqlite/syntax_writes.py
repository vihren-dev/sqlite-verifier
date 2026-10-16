"""Map transaction control, INSERT, UPDATE and DELETE to statement syntax.

INSERT keeps its optional column list, its VALUES rows and its RETURNING columns;
UPDATE keeps its assignments, its optional WHERE expression and its RETURNING
columns; DELETE keeps its optional WHERE expression and its RETURNING columns. Values, assignments and the filter are query expressions
(`syntax_queries.query_expression`); Lean decides which of them the model admits in a
write. A write with RETURNING is a `returning` node around the write, with its
result columns as in SELECT; a write without RETURNING is the write alone.
The ON CONFLICT clauses of INSERT are `syntax_conflicts.conflict_clauses`; an INSERT
without them has an empty list. The algorithm of `INSERT OR algorithm` and `REPLACE INTO`
is `syntax_conflicts.insert_algorithm`. `UPDATE OR`, FROM, SELECT sources and named or
non-deferred transactions have no constructor and are refused with their source range.
"""

from .located import Located, constructor, leaf, sequence
from .sql_tree import Node, Tree
from .syntax_conflicts import assignment_list, conflict_clauses, insert_algorithm
from .syntax_definitions import absent, left_list, require
from .syntax_expressions import name
from .syntax_queries import query_expression, result_columns


def transaction(tree: Tree, command: Node) -> Located:
    """Map BEGIN [DEFERRED] [TRANSACTION], COMMIT or END [TRANSACTION], and ROLLBACK [TRANSACTION]."""
    children = tree.children(command)
    keyword = children[0].symbol
    if keyword == "BEGIN":
        _, mode, option = require(tree, command, ["BEGIN", "transtype", "trans_opt"])
        if [child.symbol for child in tree.children(mode)] not in ([], ["DEFERRED"]):
            raise tree.unsupported(mode, "Only deferred transactions are modeled; write BEGIN or BEGIN DEFERRED")
    else:
        _, option = require(tree, command, [keyword, "trans_opt"])
    if [child.symbol for child in tree.children(option)] not in ([], ["TRANSACTION"]):
        raise tree.unsupported(option, "Named transactions are not modeled; remove the transaction name")
    kind = {"BEGIN": "begin", "COMMIT": "commit", "END": "commit", "ROLLBACK": "rollback"}[keyword]
    return leaf(kind, command.start, command.end)


def value_rows(tree: Tree, node: Node) -> Located:
    """Map the VALUES rows of an INSERT source, in source order; a SELECT source is refused."""
    current = node
    for symbol in ("selectnowith", "oneselect"):
        (current,) = require(tree, current, [symbol])
    children = tree.children(current)
    if [child.symbol for child in children] not in (["values"], ["mvalues"]):
        raise tree.unsupported(current, "Only VALUES rows are modeled as an INSERT source; "
                               "write INSERT ... VALUES (...)")
    current, listed = children[0], []
    while current.symbol == "mvalues":
        earlier = tree.children(current)[0].symbol if current.children else ""
        parts = require(tree, current, [earlier, "COMMA", "LP", "nexprlist", "RP"])
        listed.append(parts[3])
        current = parts[0]
    listed.append(require(tree, current, ["VALUES", "LP", "nexprlist", "RP"])[2])
    rows = [sequence([query_expression(tree, item[-1]) for item in
                      left_list(tree, row, {1: ["expr"], 3: ["nexprlist", "COMMA", "expr"]})], row.start, row.end)
            for row in reversed(listed)]
    return sequence(rows, node.start, node.end)


def returning(tree: Tree, command: Node, write: Located, parts: list[Node]) -> Located:
    """The write, or a `returning` node around it with the columns of the parts
    `RETURNING selcollist`."""
    if not parts:
        return write
    return constructor("returning", [("write", write), ("columns", result_columns(tree, parts[1]))],
                       command.start, command.end)


def insert(tree: Tree, command: Node) -> Located:
    """Map INSERT [OR algorithm] INTO table [(columns)] VALUES rows [ON CONFLICT ...]
    [RETURNING columns], and REPLACE INTO."""
    with_, operation, _, target, columns, source, upsert = require(
        tree, command, ["with", "insert_cmd", "INTO", "xfullname", "idlist_opt", "select", "upsert"])
    absent(tree, with_, "A WITH clause")
    algorithm = insert_algorithm(tree, operation)
    conflicts, returned = conflict_clauses(tree, upsert)
    (table,) = require(tree, target, ["nm"])
    if columns.children:
        _, listed, _ = require(tree, columns, ["LP", "idlist", "RP"])
        names = [name(tree, item[-1]) for item in left_list(tree, listed, {1: ["nm"], 3: ["idlist", "COMMA", "nm"]})]
        column_list = sequence(names, columns.start, columns.end)
    else:
        column_list = leaf(None, columns.start, columns.end)
    write = constructor("insert", [("table", name(tree, table)), ("columns", column_list),
                                   ("rows", value_rows(tree, source)), ("conflicts", conflicts),
                                   ("algorithm", algorithm)],
                        command.start, command.end)
    return returning(tree, command, write, returned)


def update(tree: Tree, command: Node) -> Located:
    """Map UPDATE table SET assignments [WHERE expression] [RETURNING columns]."""
    with_, _, conflict, target, indexed, _, assignments, from_, where = require(
        tree, command, ["with", "UPDATE", "orconf", "xfullname", "indexed_opt", "SET", "setlist", "from",
                        "where_opt_ret"])
    absent(tree, with_, "A WITH clause")
    absent(tree, conflict, "An OR conflict clause")
    absent(tree, indexed, "INDEXED BY")
    absent(tree, from_, "UPDATE FROM")
    (table,) = require(tree, target, ["nm"])
    filter_, returned = filter_and_returning(tree, where, "UPDATE")
    write = constructor("update", [("table", name(tree, table)),
                                   ("assignments", assignment_list(tree, assignments)),
                                   ("filter", filter_)], command.start, command.end)
    return returning(tree, command, write, returned)


def filter_and_returning(tree: Tree, where: Node, statement: str) -> tuple[Located, list[Node]]:
    """The optional WHERE filter and the `RETURNING selcollist` parts of a `where_opt_ret`
    node, which UPDATE and DELETE share; a missing filter is a null leaf."""
    parts = tree.children(where)
    symbols = [part.symbol for part in parts]
    if symbols not in ([], ["WHERE", "expr"], ["RETURNING", "selcollist"], ["WHERE", "expr", "RETURNING", "selcollist"]):
        raise tree.unsupported(where, f"Unsupported {statement} clause; write [WHERE expression] [RETURNING columns]")
    filter_ = query_expression(tree, parts[1]) if symbols[:1] == ["WHERE"] else leaf(None, where.start, where.end)
    return filter_, (parts[-2:] if symbols[-2:] == ["RETURNING", "selcollist"] else [])


def delete(tree: Tree, command: Node) -> Located:
    """Map DELETE FROM table [WHERE expression] [RETURNING columns]."""
    with_, _, _, target, indexed, where = require(
        tree, command, ["with", "DELETE", "FROM", "xfullname", "indexed_opt", "where_opt_ret"])
    absent(tree, with_, "A WITH clause")
    absent(tree, indexed, "INDEXED BY")
    (table,) = require(tree, target, ["nm"])
    filter_, returned = filter_and_returning(tree, where, "DELETE")
    write = constructor("delete", [("table", name(tree, table)), ("filter", filter_)], command.start, command.end)
    return returning(tree, command, write, returned)
