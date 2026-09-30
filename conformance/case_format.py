"""Version-one structural JSON shared by compiled conformance and proof emission."""

from typing import TypeAlias

from migration_check.sql_model import Column, Statement, Table
from migration_check.sql_values import SqlValue
from conformance.native_connection import Cell

Json: TypeAlias = None | bool | int | str | list["Json"] | dict[str, "Json"]


def column_wire(column: Column) -> dict[str, Json]:
    """Preserve every supported declaration field rather than only affinity."""
    return {"name": column.name, "affinity": column.affinity,
            "declaredType": column.declared_type, "notNull": column.not_null,
            "defaultValue": "currentTimestamp" if column.current_timestamp else None}


def schema_wire(table: Table) -> dict[str, Json]:
    """Encode schema constructors using Lean's derived, named-field JSON representation."""
    return {"name": table.name, "columns": [column_wire(c) for c in table.columns],
            "properties": {"primaryKey": list(table.primary_key),
                           "uniqueKeys": [list(key) for key in table.unique_keys],
                           "indexes": [{"name": index.name, "columns": list(index.columns),
                                        "unique": index.unique}
                                       for index in sorted(table.indexes, key=lambda item: item.name)]}}


def cell_wire(cell: Cell) -> Json:
    """TEXT and BLOB are byte arrays; REAL is its unsigned 64-bit decimal bit string."""
    kind, value = cell
    if kind == 5 and value is None:
        return "null"
    if kind in (1, 2) and isinstance(value, int):
        return {"integer": {"value": value}} if kind == 1 else {"real": {"bits": str(value)}}
    if kind in (3, 4) and isinstance(value, bytes):
        return {"text" if kind == 3 else "blob": {"bytes": list(value)}}
    raise ValueError("Invalid typed SQLite cell")


def literal_cell(value: SqlValue) -> Cell:
    """Interpret supported frontend literals without affinity conversion."""
    if value is None:
        return 5, None
    if isinstance(value, int):
        return 1, value
    return (3, value.encode()) if isinstance(value, str) else (4, value)


def statement_wire(statement: Statement) -> Json:
    """Serialize all seven production statement constructors without parsing Lean source."""
    kind = statement.kind
    if kind in ("beginTransaction", "commit", "rollback"):
        return kind
    if kind == "createTable":
        return {kind: {"name": statement.table, "columns": [column_wire(c) for c in statement.columns]}}
    if kind == "addColumn":
        return {kind: {"table": statement.table, "column": column_wire(statement.columns[0])}}
    if kind == "insert":
        return {kind: {"table": statement.table, "columns": list(statement.names),
                       "values": [cell_wire(literal_cell(v)) for v in statement.values]}}
    return {kind: {"table": statement.table, "column": statement.names[0],
                   "value": cell_wire(literal_cell(statement.values[0])),
                   "key": statement.key, "equals": statement.equals}}


def table_wire(table: Table, rows: list[tuple[int, tuple[Cell, ...]]]) -> dict[str, Json]:
    """Attach exact physical rows to the same schema encoding used by the frontend."""
    metadata = schema_wire(table)
    return {"columns": metadata["columns"], "properties": metadata["properties"],
            "rows": [{"rowid": rowid, "values": [cell_wire(cell) for cell in cells]}
                     for rowid, cells in rows]}
