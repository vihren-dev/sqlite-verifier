"""Versioned SQLite evidence independent of frontend admission or model constructors."""

from contextlib import ExitStack
import ctypes as c
from pathlib import Path
from tempfile import TemporaryDirectory
import time
from collections.abc import Iterator

from conformance.case_format import Json, cell_wire
from conformance.native_connection import Cell, Row, Connection, NativeError, SOURCE_ID, library_path, load_library
from conformance.native_metadata import integer, quoted, text


def wire_rows(rows: list[Row]) -> list[Json]:
    """Preserve native storage classes in metadata as well as application values."""
    return [[cell_wire(cell) for cell in row] for row in rows]


def observe(connection: Connection) -> dict[str, Json]:
    """Record all schema objects and readable rows without asking the translator."""
    if any(text(row[1]) not in ("main", "temp") for row in connection.query("PRAGMA database_list;")):
        raise ValueError("Excluded connection context: attached database")
    if connection.query("SELECT name FROM sqlite_temp_schema;"):
        raise ValueError("Excluded connection context: temporary schema")
    schema = connection.query("SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name;")
    inventory = {text(row[1]): row for row in connection.query("PRAGMA table_list;") if text(row[0]) == "main"}
    tables: list[Json] = []
    for kind, name_cell, _, _ in schema:
        if text(kind) not in ("table", "view"):
            continue
        name = text(name_cell)
        columns = connection.query(f"PRAGMA table_xinfo({quoted(name)});")
        visible = [row for row in columns if integer(row[6]) != 1]
        names = [text(row[1]) for row in visible]
        without_rowid = bool(integer(inventory[name][4]))
        key = [text(row[1]) for row in sorted(visible, key=lambda row: integer(row[5])) if integer(row[5])]
        rowid = next((alias for alias in ("rowid", "_rowid_", "oid")
                      if alias not in {n.lower() for n in names}), None)
        if not without_rowid and text(kind) == "table" and rowid:
            key = [rowid]
        elif text(kind) == "view" or not without_rowid:
            key = names  # No exposed physical identity: retain the complete ordered multiset.
        ordering = ",".join(quoted(n) for n in key)
        identities = connection.query(f"SELECT {ordering} FROM {quoted(name)} ORDER BY {ordering};")
        values: list[list[Cell]] = [[] for _ in identities]
        for offset in range(0, len(names), 2000):
            selected = ",".join(quoted(n) for n in names[offset:offset + 2000])
            chunk = connection.query(f"SELECT {selected} FROM {quoted(name)} ORDER BY {ordering};")
            if len(chunk) != len(identities):
                raise ValueError("Native rows changed during observation")
            for destination, row in zip(values, chunk, strict=True):
                destination.extend(row)
        indexes = connection.query(f"PRAGMA index_list({quoted(name)});")
        tables.append({"name": name, "kind": text(kind), "withoutRowid": without_rowid,
            "columns": wire_rows(columns), "indexes": [
                {"entry": wire_rows([entry])[0], "columns": wire_rows(connection.query(
                    f"PRAGMA index_xinfo({quoted(text(entry[1]))});"))} for entry in indexes],
            "foreignKeys": wire_rows(connection.query(f"PRAGMA foreign_key_list({quoted(name)});")),
            "rowKey": key, "rows": [{"identity": wire_rows([identity])[0], "values": wire_rows([tuple(row)])[0]}
                                     for identity, row in zip(identities, values, strict=True)]})
    return {"schema": wire_rows(schema), "tables": tables}


def execute(connection: Connection, sql: str) -> Iterator[dict[str, Json]]:
    """Use SQLite's prepared-statement tail to split SQL, including trigger bodies."""
    remaining = sql.encode()
    while remaining.strip():
        statement, tail = c.c_void_p(), c.c_char_p()
        connection.deadline = time.monotonic() + 5
        code = connection.library.sqlite3_prepare_v2(connection.handle, remaining, len(remaining),
                                                      c.byref(statement), c.byref(tail))
        suffix = tail.value or b""
        consumed = remaining[:len(remaining) - len(suffix)]
        rows: list[Row] = []
        message = ""
        try:
            connection.check(code)
            if statement.value:
                while True:
                    result = connection.library.sqlite3_step(statement)
                    connection.check(result)
                    if result == 101:
                        break
                    rows.append(tuple(connection.cell(statement, index) for index in range(
                        connection.library.sqlite3_column_count(statement))))
        except NativeError as error:
            code, message = error.code, str(error)
            if code & 255 not in (1, 19):
                raise
        finally:
            connection.library.sqlite3_finalize(statement)
        if statement.value or code:
            yield {"sql": consumed.decode(), "rows": wire_rows(rows),
                   "primaryCode": code & 255, "extendedCode": code, "error": message}
        if code:
            return
        if remaining == suffix:
            raise ValueError("SQLite made no progress parsing SQL")
        remaining = suffix


def record_sql(setup: str, migration: str, *, name: str, requirements: list[str] | None = None,
               library: Path | None = None) -> dict[str, Json]:
    """Keep native evidence even when today's frontend cannot represent the SQL."""
    with TemporaryDirectory(prefix="native-corpus-") as directory, ExitStack() as stack:
        engine = load_library(library or library_path())
        writer = Connection(engine, Path(directory) / "case.db")
        stack.callback(writer.close)
        writer.execute_script(setup)
        if writer.transaction_open:
            raise ValueError("Corpus setup must end outside a transaction")
        reader = Connection(engine, Path(directory) / "case.db")
        stack.callback(reader.close)

        def snapshot() -> dict[str, Json]:
            """Preserve committed observations independently while a transaction is open."""
            visible = observe(writer)
            return {"visible": visible, "persisted": observe(reader) if writer.transaction_open else visible,
                    "transactionOpen": writer.transaction_open}

        initial = snapshot()
        trace = [{**event, **snapshot()} for event in execute(writer, migration)]
    return {"nativeVersion": 1, "name": name, "setupSql": setup, "migrationSql": migration,
            "sourceId": SOURCE_ID, "requirements": requirements or [], "initial": initial, "trace": trace}
