"""Tail-based native execution retains statement outputs without frontend parsing."""

from collections.abc import Iterator
import ctypes as c
import time

from conformance.case_format import Json, cell_wire
from conformance.native_connection import Cell, Row, Connection, NativeError, SQL_ERRORS


def wire_rows(rows: list[Row]) -> list[Json]:
    """Preserve native storage classes in metadata as well as application values."""
    return [[cell_wire(cell) for cell in row] for row in rows]


def execute(connection: Connection, sql: str, *, outputs: bool = False,
            parameters: list[tuple[Cell, ...]] | None = None) -> Iterator[dict[str, Json]]:
    """Use SQLite's prepared-statement tail to split SQL, including trigger bodies."""
    if parameters is not None and not outputs:
        raise ValueError("Bound parameters require output recording")
    if outputs and not hasattr(connection, "statement_actions"):
        raise ValueError("Output recording requires the native acquisition authorizer")
    bindings = iter(parameters or [])
    remaining = sql.encode()
    while remaining.strip():
        statement, tail = c.c_void_p(), c.c_char_p()
        connection.deadline = time.monotonic() + 5
        if outputs:
            connection.statement_actions.clear()
        code = connection.library.sqlite3_prepare_v2(connection.handle, remaining, len(remaining),
                                                      c.byref(statement), c.byref(tail))
        suffix = tail.value or b""
        consumed = remaining[:len(remaining) - len(suffix)]
        rows: list[Row] = []
        columns: list[str] = []
        bound: tuple[Cell, ...] = next(bindings, ()) if outputs and (statement.value or code) else ()
        changes: int | None = None
        message = ""
        try:
            connection.check(code)
            if statement.value:
                if outputs:
                    if connection.library.sqlite3_bind_parameter_count(statement) != len(bound):
                        raise ValueError("Expected one typed value per SQLite parameter slot")
                    columns = [connection.library.sqlite3_column_name(statement, index).decode()
                               for index in range(connection.library.sqlite3_column_count(statement))]
                    if not connection.library.sqlite3_stmt_readonly(statement):
                        from conformance.native_ordering import check_write_window
                        check_write_window(connection, consumed.decode(), bound)
                    for index, cell in enumerate(bound, 1):
                        connection.bind(statement, index, cell)
                while True:
                    result = connection.library.sqlite3_step(statement)
                    connection.check(result)
                    if result == 101:
                        break
                    rows.append(tuple(connection.cell(statement, index) for index in range(
                        connection.library.sqlite3_column_count(statement))))
        except NativeError as error:
            if getattr(connection, "recording_exclusion", None):
                raise ValueError(connection.recording_exclusion) from error
            code, message = error.code, str(error)
            if code & 255 not in SQL_ERRORS:
                raise
        finally:
            if outputs and statement.value:
                actions = set(connection.statement_actions)
                # Native authorizer actions: DML 9/18/23; exclude schema operations.
                ddl = set(range(1, 18)) - {9}
                ddl.update(range(26, 31))
                if actions & {9, 18, 23} and not actions & ddl and not connection.library.sqlite3_stmt_isexplain(statement):
                    changes = connection.library.sqlite3_changes(connection.handle)
            connection.library.sqlite3_finalize(statement)
        if statement.value or code:
            event: dict[str, Json] = {"sql": consumed.decode(), "rows": wire_rows(rows),
                "primaryCode": code & 255, "extendedCode": code, "error": message}
            if outputs:
                from conformance.native_ordering import query_groups
                groups = query_groups(connection, consumed.decode(), bound, columns, rows) if not code and changes is None else None
                event.update({"groups": groups, "columns": columns, "columnCount": len(columns),
                              "parameters": [cell_wire(cell) for cell in bound], "changes": changes})
            yield event
        if code:
            return
        if remaining == suffix:
            raise ValueError("SQLite made no progress parsing SQL")
        remaining = suffix

    if outputs and next(bindings, None) is not None:
        raise ValueError("Parameters supplied for an unexecuted statement")
