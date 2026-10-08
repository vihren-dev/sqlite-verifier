"""Record native schema and readable row observations independently of SQL admission."""

from conformance.case_format import Json
from conformance.native_connection import Connection, Cell
from conformance.native_metadata import integer, quoted, text
from conformance.native_statements import wire_rows

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


