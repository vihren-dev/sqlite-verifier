"""Normalized SQLite declarations and statements shared by frontend consumers."""

from dataclasses import dataclass, replace
from typing import Literal, TypeAlias

SqlValue: TypeAlias = int | str | bytes | None
"""Stored SQL literals accepted by the normalized frontend."""

Affinity = Literal["integer", "real", "text", "blob", "numeric"]
DeclaredType = Literal["canonical", "bigInt", "timestamp", "boolean", "untyped"]


@dataclass(frozen=True)
class Column:
    """A column with exact supported declared type and baseline constraint metadata."""

    name: str
    affinity: Affinity
    declared_type: DeclaredType = "canonical"
    not_null: bool = False
    current_timestamp: bool = False


@dataclass(frozen=True)
class Index:
    """An ordinary explicit index over existing columns, with BINARY collation."""

    name: str
    columns: tuple[str, ...]
    unique: bool = False


@dataclass(frozen=True)
class Table:
    """A normalized ordinary rowid table in the finite starting or resulting schema."""

    name: str
    columns: tuple[Column, ...]
    primary_key: tuple[str, ...] = ()
    unique_keys: tuple[tuple[str, ...], ...] = ()
    indexes: tuple[Index, ...] = ()


@dataclass(frozen=True)
class Statement:
    """One admitted command with original coordinates for generated diagnostics."""

    kind: Literal["createTable", "addColumn", "beginTransaction", "commit", "rollback", "insert", "update"]
    table: str
    columns: tuple[Column, ...]
    source: str
    start: int
    end: int
    names: tuple[str, ...] = ()
    values: tuple[SqlValue, ...] = ()
    key: str = ""
    equals: int = 0


def transition(schema: tuple[Table, ...], script: tuple[Statement, ...]) -> tuple[tuple[Table, ...], str]:
    """Compute schema effects through static DDL/transaction errors; write errors depend on data."""
    tables = list(schema)
    saved: tuple[Table, ...] | None = None
    for statement in script:
        if statement.kind == 'beginTransaction':
            if saved is not None:
                return tuple(tables), 'transactionAlreadyActive'
            saved = tuple(tables)
            continue
        if statement.kind in {'commit', 'rollback'}:
            if saved is None:
                return tuple(tables), 'noActiveTransaction'
            if statement.kind == 'rollback':
                tables = list(saved)
            saved = None
            continue
        if statement.kind in {'insert', 'update'}:
            continue
        found = next((i for i, table in enumerate(tables) if table.name == statement.table), None)
        if statement.kind == "createTable":
            if found is not None:
                return tuple(tables), "tableExists"
            tables.append(Table(statement.table, statement.columns))
        elif found is None:
            return tuple(tables), "missingTable"
        elif len(tables[found].columns) >= 2000:
            return tuple(tables), "tooManyColumns"
        elif statement.columns[0].name in {column.name for column in tables[found].columns}:
            return tuple(tables), "columnExists"
        else:
            tables[found] = replace(tables[found], columns=tables[found].columns + statement.columns)
    return tuple(tables), ""


