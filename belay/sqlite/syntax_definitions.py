"""Map CREATE TABLE, CREATE INDEX and ALTER TABLE ADD COLUMN to statement syntax.

Each production maps to one constructor without reading the schema. Optional
syntax that has no constructor, such as TEMP, IF NOT EXISTS, a schema name, a
named constraint or a partial index, is refused with its source range.
"""

from .located import Located, constructor, leaf, sequence, structure
from .sql_tree import Node, Tree
from .syntax_expressions import dequote, expression, identifier, name, term

MODELED_FORMS = ("rewrite it with the modeled forms: CREATE TABLE, CREATE [UNIQUE] INDEX, ALTER TABLE ADD COLUMN, "
                 "BEGIN, COMMIT, ROLLBACK, INSERT ... VALUES, UPDATE ... SET ... [WHERE column = value] and "
                 "SELECT ... FROM table [WHERE] [GROUP BY] [ORDER BY] [LIMIT]")
"""The corrective action for a production that has no syntax constructor."""


def require(tree: Tree, node: Node, symbols: list[str]) -> list[Node]:
    """Return the children of a production with exactly these symbols, or refuse it."""
    children = tree.children(node)
    if [child.symbol for child in children] != symbols:
        raise tree.unsupported(node, f"Unsupported SQL form: {node.symbol}; {MODELED_FORMS}")
    return children


def absent(tree: Tree, node: Node, feature: str) -> None:
    """Refuse optional syntax that is present."""
    if node.children:
        raise tree.unsupported(node, f"{feature} is not modeled; remove it")


def left_list(tree: Tree, node: Node, shapes: dict[int, list[str]]) -> list[list[Node]]:
    """Flatten a left-recursive list in source order; an empty list node ends the list.

    `shapes` maps the child count of a list node to its symbols. Each item is the
    children of one list node after the nested list node.
    """
    items: list[list[Node]] = []
    while node.children:
        children = tree.children(node)
        expected = shapes.get(len(children))
        if expected is None or [child.symbol for child in children] != expected:
            raise tree.unsupported(node, f"Unsupported SQL form: {node.symbol}; {MODELED_FORMS}")
        if children[0].symbol != node.symbol:
            items.append(children)
            break
        items.append(children[1:])
        node = children[0]
    return list(reversed(items))


def sort_names(tree: Tree, node: Node) -> Located:
    """Map a key column list of plain names, without sort order, collation or expressions."""
    names: list[Located] = []
    for item in left_list(tree, node, {3: ["expr", "sortorder", "nulls"],
                                       5: ["sortlist", "COMMA", "expr", "sortorder", "nulls"]}):
        expression_node, order, nulls = item[-3:]
        absent(tree, order, "A sort order in a key")
        absent(tree, nulls, "NULLS FIRST or NULLS LAST")
        names.append(name(tree, require(tree, expression_node, ["ID"])[0]))
    return sequence(names, node.start, node.end)


ALGORITHMS = {"ROLLBACK": "rollback", "ABORT": "abort", "FAIL": "fail", "IGNORE": "ignore", "REPLACE": "replace"}
"""SQLite's conflict algorithm keywords and the Lean constructors of `ConflictAlgorithm`."""


def resolve_type(tree: Tree, node: Node) -> Located:
    """Map a `resolvetype` node, `raisetype`, `IGNORE` or `REPLACE`, to its algorithm."""
    (part,) = tree.children(node)
    if part.symbol == "raisetype":
        (part,) = tree.children(part)
    return leaf(ALGORITHMS[part.symbol], node.start, node.end)


def constraint_algorithm(tree: Tree, node: Node) -> Located:
    """Map an `onconf` node: the algorithm of `ON CONFLICT algorithm`, or none."""
    if not node.children:
        return leaf(None, node.start, node.end)
    _, _, kind = require(tree, node, ["ON", "CONFLICT", "resolvetype"])
    return resolve_type(tree, kind)


def column_constraint(tree: Tree, node: Node) -> Located:
    """Map NOT NULL, PRIMARY KEY with its sort order, UNIQUE, each with its ON CONFLICT
    algorithm, and the DEFAULT forms."""
    children = tree.children(node)
    symbols = [child.symbol for child in children]
    if symbols == ["NOT", "NULL", "onconf"]:
        return constructor("notNull", [("algorithm", constraint_algorithm(tree, children[2]))], node.start, node.end)
    if symbols == ["PRIMARY", "KEY", "sortorder", "onconf", "autoinc"]:
        absent(tree, children[4], "AUTOINCREMENT")
        order = [child.symbol for child in tree.children(children[2])]
        return constructor("primaryKey", [("descending", leaf(order == ["DESC"], children[2].start, children[2].end)),
                                          ("algorithm", constraint_algorithm(tree, children[3]))],
                           node.start, node.end)
    if symbols == ["UNIQUE", "onconf"]:
        return constructor("unique", [("algorithm", constraint_algorithm(tree, children[1]))], node.start, node.end)
    if symbols == ["DEFAULT", "scantok", "term"]:
        value = term(tree, children[2])
    elif symbols in (["DEFAULT", "MINUS", "scantok", "term"], ["DEFAULT", "PLUS", "scantok", "term"]):
        kind = "negate" if symbols[1] == "MINUS" else "positive"
        value = constructor(kind, [("operand", term(tree, children[3]))], children[1].start, children[3].end)
    elif symbols == ["DEFAULT", "scantok", "ID"]:
        value = identifier(tree, children[2])
    else:
        raise tree.unsupported(node, "Unsupported column constraint; use NOT NULL, PRIMARY KEY, UNIQUE or "
                               "DEFAULT with a literal")
    return constructor("default", [("value", value)], node.start, node.end)


def column_definition(tree: Tree, column: Node, constraints: Node) -> Located:
    """Map a column name, its declared type text as SQLite keeps it, and its constraints."""
    column_name, type_token = require(tree, column, ["nm", "typetoken"])
    declared = dequote(tree.text(type_token)) if type_token.children else None
    items = [column_constraint(tree, item[-1]) for item in left_list(tree, constraints, {2: ["carglist", "ccons"]})]
    return structure([("name", name(tree, column_name)),
                      ("declaredType", leaf(declared, type_token.start, type_token.end)),
                      ("constraints", sequence(items, constraints.start, constraints.end))],
                     column.start, constraints.end)


def table_constraint(tree: Tree, node: Node) -> Located:
    """Map a table PRIMARY KEY or UNIQUE constraint over plain column names, with its
    ON CONFLICT algorithm."""
    children = tree.children(node)
    symbols = [child.symbol for child in children]
    if symbols == ["PRIMARY", "KEY", "LP", "sortlist", "autoinc", "RP", "onconf"]:
        absent(tree, children[4], "AUTOINCREMENT")
        return constructor("primaryKey", [("columns", sort_names(tree, children[3])),
                                          ("algorithm", constraint_algorithm(tree, children[6]))], node.start, node.end)
    if symbols == ["UNIQUE", "LP", "sortlist", "RP", "onconf"]:
        return constructor("unique", [("columns", sort_names(tree, children[2])),
                                      ("algorithm", constraint_algorithm(tree, children[4]))], node.start, node.end)
    raise tree.unsupported(node, "Unsupported table constraint; use PRIMARY KEY or UNIQUE over column names")


def create_table(tree: Tree, command: Node) -> Located:
    """Map CREATE TABLE with column definitions and table constraints."""
    declaration, arguments = require(tree, command, ["create_table", "create_table_args"])
    header = require(tree, declaration, ["createkw", "temp", "TABLE", "ifnotexists", "nm", "dbnm"])
    body = require(tree, arguments, ["LP", "columnlist", "conslist_opt", "RP", "table_option_set"])
    absent(tree, header[1], "TEMP")
    absent(tree, header[3], "IF NOT EXISTS")
    absent(tree, header[5], "A schema name")
    absent(tree, body[4], "A table option such as WITHOUT ROWID or STRICT")
    column_shapes = {2: ["columnname", "carglist"], 4: ["columnlist", "COMMA", "columnname", "carglist"]}
    columns = [column_definition(tree, item[-2], item[-1]) for item in left_list(tree, body[1], column_shapes)]
    constraints: list[Located] = []
    if body[2].children:
        _, listed = require(tree, body[2], ["COMMA", "conslist"])
        constraints = [table_constraint(tree, item[-1]) for item in
                       left_list(tree, listed, {1: ["tcons"], 3: ["conslist", "tconscomma", "tcons"]})]
    return constructor("createTable", [("name", name(tree, header[4])),
                                       ("columns", sequence(columns, body[1].start, body[1].end)),
                                       ("constraints", sequence(constraints, body[2].start, body[2].end))],
                       command.start, command.end)


def create_index(tree: Tree, command: Node) -> Located:
    """Map CREATE [UNIQUE] INDEX over plain column names, without a WHERE clause."""
    parts = require(tree, command, ["createkw", "uniqueflag", "INDEX", "ifnotexists", "nm", "dbnm", "ON", "nm",
                                    "LP", "sortlist", "RP", "where_opt"])
    absent(tree, parts[3], "IF NOT EXISTS")
    absent(tree, parts[5], "A schema name")
    absent(tree, parts[11], "A partial index WHERE clause")
    return constructor("createIndex", [("name", name(tree, parts[4])),
                                       ("unique", leaf(bool(parts[1].children), parts[1].start, parts[1].end)),
                                       ("table", name(tree, parts[7])),
                                       ("columns", sort_names(tree, parts[9]))], command.start, command.end)


def add_column(tree: Tree, command: Node) -> Located:
    """Map ALTER TABLE ADD [COLUMN] for an unqualified table name."""
    parts = require(tree, command, ["ALTER", "TABLE", "add_column_fullname", "ADD", "kwcolumn_opt", "columnname",
                                    "carglist"])
    (full,) = require(tree, parts[2], ["fullname"])
    (table,) = require(tree, full, ["nm"])
    return constructor("addColumn", [("table", name(tree, table)),
                                     ("column", column_definition(tree, parts[5], parts[6]))],
                       command.start, command.end)
