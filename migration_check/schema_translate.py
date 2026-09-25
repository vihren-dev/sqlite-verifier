"""Translate complete declarative schemas, including preserved keys and indexes."""

from dataclasses import replace

from .diagnostics import Rejection
from .schema_syntax import baseline_column, key_columns, unique_keys
from .sql_model import Column, Index, Statement, Table
from .sql_tree import Node, Tree
from .translate import commands, empty, identifier


def table_definition(tree: Tree, command: Node) -> Table:
    """Require an ordinary rowid table with explicit supported columns and constraints."""
    declaration, arguments = tree.children(command)
    header, body = tree.children(declaration), tree.children(arguments)
    if ([item.symbol for item in header] != ["createkw", "temp", "TABLE", "ifnotexists", "nm", "dbnm"]
            or [item.symbol for item in body] != ["LP", "columnlist", "conslist_opt", "RP", "table_option_set"]):
        raise tree.unsupported(command, "Only ordinary explicit table definitions are supported")
    for item in [header[1], header[3], header[5], body[4]]:
        empty(tree, item)
    columns: list[Column] = []
    primary: list[str] = []
    current = body[1]
    while True:
        members = tree.children(current)
        symbols = [item.symbol for item in members]
        if symbols == ["columnname", "carglist"]:
            prior, name, constraints = None, *members
        elif symbols == ["columnlist", "COMMA", "columnname", "carglist"]:
            prior, name, constraints = members[0], *members[2:]
        else:
            raise tree.unsupported(current, "Unsupported table column list")
        definition, is_primary = baseline_column(tree, name, constraints)
        columns.append(definition)
        if is_primary:
            primary.append(definition.name)
            if definition.affinity == "integer" and definition.declared_type == "canonical":
                raise tree.unsupported(name, "INTEGER PRIMARY KEY rowid aliases are not modeled")
        if prior is None:
            break
        current = prior
    columns.reverse()
    if len(columns) > 2000 or len({column.name for column in columns}) != len(columns):
        raise tree.unsupported(body[1], "A supported table has at most 2000 distinct columns")
    if len(primary) > 1:
        raise tree.unsupported(body[1], "Multiple primary keys are invalid")
    return Table(identifier(tree, header[4], table=True, statistics=True), tuple(columns), tuple(primary),
                 unique_keys(tree, body[2]))


def index_definition(tree: Tree, command: Node) -> tuple[str, Index]:
    """Admit named plain-column indexes, excluding expressions and partial predicates."""
    parts = tree.children(command)
    if [item.symbol for item in parts] != [
        "createkw", "uniqueflag", "INDEX", "ifnotexists", "nm", "dbnm", "ON", "nm",
        "LP", "sortlist", "RP", "where_opt",
    ]:
        raise tree.unsupported(command, "Unsupported index definition")
    for item in [parts[3], parts[5], parts[11]]:
        empty(tree, item)
    unique = tree.children(parts[1])
    if unique and [item.symbol for item in unique] != ["UNIQUE"]:
        raise tree.unsupported(parts[1], "Unsupported index uniqueness")
    return identifier(tree, parts[7], table=True), Index(
        identifier(tree, parts[4], table=True), key_columns(tree, parts[9]), bool(unique))


def schema(tree: Tree) -> tuple[Table, ...]:
    """Resolve all schema objects and references independently of export enumeration order."""
    tables: dict[str, Table] = {}
    indexes: list[tuple[str, Index]] = []
    names: set[str] = set()
    for command in commands(tree):
        symbols = [item.symbol for item in tree.children(command)]
        if symbols == ["create_table", "create_table_args"]:
            table = table_definition(tree, command)
            name = table.name
            tables[name] = table
        elif symbols[:3] == ["createkw", "uniqueflag", "INDEX"]:
            owner, index = index_definition(tree, command)
            name = index.name
            indexes.append((owner, index))
        else:
            raise tree.unsupported(command, "Starting schema requires supported tables and indexes")
        if name in names:
            raise Rejection("INPUT_ERROR", "Starting schema contains duplicate object names", source=tree.source)
        names.add(name)
    for owner, index in indexes:
        if owner not in tables:
            raise Rejection("INPUT_ERROR", "Index references a missing table", source=tree.source)
        tables[owner] = replace(tables[owner], indexes=tables[owner].indexes + (index,))
    for table in tables.values():
        statistics = {"sqlite_stat1": ("tbl", "idx", "stat"),
                      "sqlite_stat4": ("tbl", "idx", "neq", "nlt", "ndlt", "sample")}
        if table.name in statistics:
            expected = Table(table.name, tuple(Column(name, "blob", "untyped")
                                               for name in statistics[table.name]))
            if table != expected:
                raise Rejection("UNSUPPORTED", "Statistics tables require their exact native definition",
                                source=tree.source)
        column_names = {column.name for column in table.columns}
        keys = (*table.unique_keys, *(index.columns for index in table.indexes))
        if any(not key or len(set(key)) != len(key) or not set(key) <= column_names for key in keys):
            raise Rejection("UNSUPPORTED", "Keys require distinct existing columns", source=tree.source)
    return tuple(tables.values())


def validate_migration(schema: tuple[Table, ...], script: tuple[Statement, ...]) -> None:
    """Keep CREATE away from the unmodeled global constraint/index execution namespace."""
    if any(table.primary_key or table.unique_keys or table.indexes or
           any(column.not_null or column.current_timestamp for column in table.columns) for table in schema):
        for statement in script:
            if statement.kind == "createTable":
                raise Rejection("UNSUPPORTED", "CREATE TABLE with baseline keys or indexes is not modeled",
                                source=statement.source, start=statement.start, end=statement.end)
