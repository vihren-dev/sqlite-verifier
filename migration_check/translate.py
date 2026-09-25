"""Admit complete known CST productions; every unmodeled dependency blocks checking."""

from typing import cast

from .sql_model import Affinity, Column, Statement, Table
from .sql_tree import Node, Tree


def normalize(value: str) -> str:
    """Match SQLite's ASCII-only case-insensitive identifier comparison."""
    return value.translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"))


def identifier(tree: Tree, node: Node, *, table: bool = False, statistics: bool = False) -> str:
    """Dequote SQLite identifier tokens without treating their contents as code."""
    text = tree.text(node)
    if text[:1] in ('"', "'", "`"):
        quote = text[0]
        text = text[1:-1].replace(quote * 2, quote)
    elif text.startswith("["):
        text = text[1:-1]
    name = normalize(text)
    reserved = table and name.startswith("sqlite_") and not (
        statistics and name in {"sqlite_stat1", "sqlite_stat4"})
    if not name or reserved or (
        not table and name in {"rowid", "_rowid_", "oid"}
    ):
        raise tree.unsupported(node, "Empty, reserved, or rowid-shadowing names are unsupported")
    return name


def empty(tree: Tree, node: Node) -> None:
    """Require absence of optional syntax, including constraints and object dependencies."""
    if node.children:
        raise tree.unsupported(node, f"Unsupported SQL feature: {node.symbol}")


def column(tree: Tree, node: Node, constraints: Node) -> Column:
    """Accept only the five explicit canonical type names and implicit NULL defaults."""
    empty(tree, constraints)
    children = tree.children(node)
    if [child.symbol for child in children] != ["nm", "typetoken"]:
        raise tree.unsupported(node, "Unsupported column definition")
    type_children = tree.children(children[1])
    if len(type_children) != 1 or type_children[0].symbol != "typename":
        raise tree.unsupported(children[1], "Use an explicit INTEGER, REAL, TEXT, BLOB, or NUMERIC type")
    tokens = tree.children(type_children[0])
    affinity = normalize(tree.text(tokens[0])) if len(tokens) == 1 else ""
    if affinity not in {"integer", "real", "text", "blob", "numeric"}:
        raise tree.unsupported(children[1], "Declared type is outside the canonical supported subset")
    return Column(identifier(tree, children[0]), cast(Affinity, affinity))


def create(tree: Tree, command: Node) -> Statement:
    """Check every CREATE TABLE production component before admitting its column list."""
    declaration, arguments = tree.children(command)
    header = tree.children(declaration)
    body = tree.children(arguments)
    if ([node.symbol for node in header] != ["createkw", "temp", "TABLE", "ifnotexists", "nm", "dbnm"]
            or [node.symbol for node in body] != ["LP", "columnlist", "conslist_opt", "RP", "table_option_set"]):
        raise tree.unsupported(command, "Only ordinary explicit CREATE TABLE definitions are supported")
    for node in [header[1], header[3], header[5], body[2], body[4]]:
        empty(tree, node)
    definitions: list[Column] = []
    # columnlist is left-recursive; reverse its collected right-hand definitions.
    current = body[1]
    while True:
        members = tree.children(current)
        symbols = [node.symbol for node in members]
        if symbols == ["columnname", "carglist"]:
            definitions.append(column(tree, members[0], members[1]))
            break
        if symbols != ["columnlist", "COMMA", "columnname", "carglist"]:
            raise tree.unsupported(current, "Unsupported table column list")
        definitions.append(column(tree, members[2], members[3]))
        current = members[0]
    definitions.reverse()
    if len(definitions) > 2000 or len({item.name for item in definitions}) != len(definitions):
        raise tree.unsupported(body[1], "A supported table has at most 2000 distinct columns")
    return Statement("createTable", identifier(tree, header[4], table=True), tuple(definitions),
                     tree.source, command.start, command.end)


def add(tree: Tree, command: Node) -> Statement:
    """Admit unqualified ALTER TABLE ADD with exactly one unconstrained nullable column."""
    members = tree.children(command)
    if [node.symbol for node in members] != [
        "ALTER", "TABLE", "add_column_fullname", "ADD", "kwcolumn_opt", "columnname", "carglist"
    ]:
        raise tree.unsupported(command, "Only ALTER TABLE ADD COLUMN is supported")
    fullname = tree.children(members[2])
    name = tree.children(fullname[0]) if len(fullname) == 1 and fullname[0].symbol == "fullname" else []
    if len(name) != 1 or name[0].symbol != "nm":
        raise tree.unsupported(members[2], "Only unqualified main-database tables are supported")
    definition = column(tree, members[5], members[6])
    return Statement("addColumn", identifier(tree, name[0], table=True), (definition,),
                     tree.source, command.start, command.end)


def commands(tree: Tree) -> list[Node]:
    """Retain every command and reject unsupported top-level wrappers."""
    result: list[Node] = []
    for node in tree.walk(tree.nodes[tree.root]):
        if node.symbol != "ecmd":
            continue
        members = tree.children(node)
        if [child.symbol for child in members] == ["SEMI"]:
            continue
        if [child.symbol for child in members] != ["cmdx", "SEMI"]:
            raise tree.unsupported(node, "Unsupported command wrapper (including EXPLAIN)")
        result.append(tree.children(members[0])[0])
    return result


def statements(tree: Tree) -> tuple[Statement, ...]:
    """Admit only the existing migration operations, independent of baseline richness."""
    result: list[Statement] = []
    for command in commands(tree):
        symbols = [child.symbol for child in tree.children(command)]
        if symbols == ["create_table", "create_table_args"]:
            result.append(create(tree, command))
        elif symbols[:2] == ["ALTER", "TABLE"]:
            result.append(add(tree, command))
        else:
            raise tree.unsupported(command, "Statement semantics are not implemented")
    return tuple(result)


def starting_schema(tree: Tree) -> tuple[Table, ...]:
    """Admit a complete declarative baseline, including modeled keys and indexes."""
    from .schema_translate import schema
    return schema(tree)
