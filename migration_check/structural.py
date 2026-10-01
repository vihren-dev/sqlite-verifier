"""Version-one structural JSON for frontend results (`docs/conformance-format-v1.md`).

One encoder serves both consumers of the Lean codec in `StructuralCodec.lean`: the
conformance runner (ADR 0004) and the bundle checker's generated inputs (ADR 0003
P3). Enum tags and field names follow Lean's derived JSON representation.
"""

from typing import TypeAlias

from .profiles import ExecutionProfile
from .sql_model import Column, Statement, Table, transition
from .sql_values import SqlValue

Json: TypeAlias = None | bool | int | str | list["Json"] | dict[str, "Json"]
Cell: TypeAlias = tuple[int, int | bytes | None]
"""A typed SQLite cell: fundamental datatype code and payload."""


def column_wire(column: Column) -> dict[str, Json]:
    """Preserve every supported declaration field rather than only affinity."""
    return {"name": column.name, "affinity": column.affinity,
            "declaredType": column.declared_type, "notNull": column.not_null,
            "defaultValue": "currentTimestamp" if column.current_timestamp else None}


def schema_wire(table: Table, *, canonical_indexes: bool = True) -> dict[str, Json]:
    """Encode schema constructors using Lean's derived, named-field JSON representation.

    Conformance cases order explicit indexes by name, to compare with native
    observations. The Lean emitter keeps declaration order, so generated inputs pass
    `canonical_indexes=False` to describe exactly what `SchemaInputs` defines.
    """
    indexes = sorted(table.indexes, key=lambda item: item.name) if canonical_indexes else table.indexes
    return {"name": table.name, "columns": [column_wire(c) for c in table.columns],
            "properties": {"primaryKey": list(table.primary_key),
                           "uniqueKeys": [list(key) for key in table.unique_keys],
                           "indexes": [{"name": index.name, "columns": list(index.columns),
                                        "unique": index.unique} for index in indexes]}}


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


def generated_inputs_wire(schema: tuple[Table, ...], script: tuple[Statement, ...],
                          profile: ExecutionProfile) -> dict[str, Json]:
    """The record the bundle checker turns into `Generated.nextSchema`, `script` and `profile`.

    `schema` lets the checker confirm the record matches the compiled starting schema.
    """
    result, _ = transition(schema, script)
    return {"version": 1, "profile": profile.lean().removeprefix("."),
            "schema": [schema_wire(table, canonical_indexes=False) for table in schema],
            "nextSchema": [schema_wire(table, canonical_indexes=False) for table in result],
            "script": [statement_wire(statement) for statement in script]}
