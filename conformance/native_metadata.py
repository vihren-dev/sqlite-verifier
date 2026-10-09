"""Independent PRAGMA checks for the translated subset of native SQLite metadata."""

from belay.sqlite.sql_model import Affinity, Table
from conformance.native_connection import Cell, Row, Connection


def quoted(name: str) -> str:
    """Quote an admitted identifier without treating its contents as SQL."""
    return '"' + name.replace('"', '""') + '"'


def text(cell: Cell) -> str:
    """Decode metadata only; application TEXT remains arbitrary bytes."""
    kind, value = cell
    if kind != 3 or not isinstance(value, bytes):
        raise ValueError("Expected native textual schema metadata")
    return value.decode("utf-8")


def identifier(cell: Cell) -> str:
    """Compare SQLite identifiers with ASCII case folding, independently of the translator."""
    return text(cell).translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"))


def integer(cell: Cell) -> int:
    """Reject coerced native metadata and rowids."""
    kind, value = cell
    if kind != 1 or not isinstance(value, int):
        raise ValueError("Expected native integer")
    return value


def affinity(declaration: str) -> Affinity:
    """Apply SQLite datatype3.html section 3.1 in precedence order, independently."""
    name = declaration.upper()
    if "INT" in name:
        return "integer"
    if any(part in name for part in ("CHAR", "CLOB", "TEXT")):
        return "text"
    if not name or "BLOB" in name:
        return "blob"
    if any(part in name for part in ("REAL", "FLOA", "DOUB")):
        return "real"
    return "numeric"


def check_metadata(connection: Connection, table: Table) -> None:
    """Fail closed if the translator disagrees with independent native inventories."""
    info = connection.query(f"PRAGMA table_xinfo({quoted(table.name)});")
    indexes = [(entry, connection.query(f"PRAGMA index_xinfo({quoted(text(entry[1]))});"))
               for entry in connection.query(f"PRAGMA index_list({quoted(table.name)});")]
    check_inventory(table, info, indexes)


def check_inventory(table: Table, info: list[Row], indexes: list[tuple[Row, list[Row]]]) -> None:
    """Cross-check live or frozen native metadata without re-executing a recorded case."""
    if len(info) != len(table.columns):
        raise ValueError("Native column inventory differs from parsed declaration")
    primary: list[tuple[int, str]] = []
    for number, (row, column) in enumerate(zip(info, table.columns, strict=True)):
        cid, name, declared, not_null, default, pk, hidden = row
        spelling = text(declared).upper()
        expected_type = {"bigInt": "BIGINT", "timestamp": "TIMESTAMP", "boolean": "BOOLEAN",
                         "untyped": "", "canonical": column.affinity.upper()}[column.declared_type]
        default_sql = None if default[0] == 5 else text(default).upper()
        if (integer(cid) != number or identifier(name) != column.name or integer(hidden) != 0
                or spelling != expected_type or affinity(spelling) != column.affinity
                or integer(not_null) != int(column.not_null)
                or default_sql != ("CURRENT_TIMESTAMP" if column.current_timestamp else None)):
            raise ValueError(f"Native column metadata differs: {table.name}.{column.name}")
        if integer(pk):
            primary.append((integer(pk), identifier(name)))
    if tuple(name for _, name in sorted(primary)) != table.primary_key:
        raise ValueError(f"Native primary key differs: {table.name}")
    explicit: set[tuple[str, tuple[str, ...], bool]] = set()
    implicit: set[tuple[str, ...]] = set()
    for (_, name, unique, origin, partial), index_columns in indexes:
        columns: list[str] = []
        for _, cid, column, descending, collation, key in index_columns:
            if not integer(key):
                continue  # Auxiliary rowid is not part of the declared index key.
            if (integer(cid) < 0 or integer(descending) or text(collation) != "BINARY"
                    or integer(cid) >= len(table.columns)
                    or identifier(column) != table.columns[integer(cid)].name):
                raise ValueError(f"Unsupported native index metadata: {text(name)}")
            columns.append(identifier(column))
        if integer(partial):
            raise ValueError(f"Unexpected partial native index: {text(name)}")
        if text(origin) == "c":
            explicit.add((identifier(name), tuple(columns), bool(integer(unique))))
        elif text(origin) in ("u", "pk") and integer(unique):
            implicit.add(tuple(columns))
        else:
            raise ValueError(f"Unexpected native index origin: {text(name)}")
    expected_implicit = set(table.unique_keys)
    if table.primary_key:
        column = next(c for c in table.columns if c.name == table.primary_key[0])
        if len(table.primary_key) != 1 or not (column.affinity == "integer" and column.declared_type == "canonical"):
            expected_implicit.add(table.primary_key)
    if implicit != expected_implicit or explicit != {(i.name, i.columns, i.unique) for i in table.indexes}:
        raise ValueError(f"Native index inventory differs: {table.name}")
