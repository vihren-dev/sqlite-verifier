"""Reject unmodeled coercions before any proof obligation can misrepresent native SQL."""

from dataclasses import replace

from .diagnostics import Rejection
from .sql_model import Column, Statement, Table
from .sql_values import SqlValue

NUMERIC_BYTES = frozenset(b'0123456789+-.eE \t\r\n\v\f')


def lossless(value: SqlValue, column: Column) -> bool:
    """Mirror the formal sufficient literal-affinity rule, without approximating conversion."""
    if value is None or isinstance(value, bytes):
        return True
    if isinstance(value, int):
        return column.affinity in {'integer', 'numeric', 'blob'}
    if column.affinity in {'text', 'blob'}:
        return True
    data = value.encode('utf-8')
    return (column.affinity in {'integer', 'numeric'} and 0 not in data
            and any(byte not in NUMERIC_BYTES for byte in data))


def key_admission(table: Table, statement: Statement) -> str:
    """Only the modeled integer/NULL unique-key comparison domain can admit a write."""
    keys = ([table.primary_key] if table.primary_key else []) + list(table.unique_keys)
    keys += [index.columns for index in table.indexes if index.unique]
    key_columns = {name for key in keys for name in key}
    columns = {column.name: column for column in table.columns}
    if any(columns[name].affinity not in {'integer', 'numeric', 'blob'} for name in key_columns):
        return 'DML unique keys require INTEGER, NUMERIC or BLOB affinity'
    if statement.kind == 'update' and (statement.key,) not in keys:
        return 'UPDATE equality requires a declared singleton unique key'
    if any(name in key_columns and value is not None and type(value) is not int
           for name, value in zip(statement.names, statement.values)):
        return 'DML key literals require signed integers or NULL'
    return ''


def validate_writes(schema: tuple[Table, ...], script: tuple[Statement, ...]) -> None:
    """Conservatively admit write syntax using schema snapshots; this does not execute the script."""
    tables = {table.name: table for table in schema}
    saved: dict[str, Table] | None = None
    for statement in script:
        if statement.kind == 'beginTransaction':
            if saved is None:
                saved = dict(tables)
        elif statement.kind == 'commit':
            saved = None
        elif statement.kind == 'rollback':
            if saved is not None:
                tables, saved = saved, None
        elif statement.kind == 'createTable' and statement.table not in tables:
            tables[statement.table] = Table(statement.table, statement.columns)
        elif statement.kind == 'addColumn' and statement.table in tables:
            table = tables[statement.table]
            if statement.columns[0].name not in {column.name for column in table.columns}:
                tables[statement.table] = replace(table, columns=table.columns + statement.columns)
        elif statement.kind in {'insert', 'update'}:
            table = tables.get(statement.table)
            reason = ''
            if table is None:
                reason = 'Literal writes require a known ordinary table schema'
            elif statement.kind == 'insert' and statement.names != tuple(column.name for column in table.columns):
                reason = 'INSERT requires every column once, in declaration order, without defaults'
            elif any(name not in {column.name for column in table.columns} for name in statement.names):
                reason = 'Assignment column is absent from the current schema'
            elif statement.kind == 'update' and statement.key not in {column.name for column in table.columns}:
                reason = 'UPDATE equality column is absent from the current schema'
            else:
                assert table is not None
                reason = key_admission(table, statement)
                columns = {column.name: column for column in table.columns}
                if not reason and any(not lossless(value, columns[name]) for name, value in zip(statement.names, statement.values)):
                    reason = 'Literal affinity conversion is outside the lossless supported subset'
            if reason:
                raise Rejection('UNSUPPORTED', reason, source=statement.source,
                                start=statement.start, end=statement.end)
