"""Read the counters of a native connection (ADR 0024, D1)."""

from conformance.native_connection import Connection


def read_counters(connection: Connection) -> dict[str, int]:
    """The three counters of the connection now: the rows changed by the last statement that
    changed rows (`sqlite3_changes64`), the rows changed since the connection opened
    (`sqlite3_total_changes64`) and the rowid of the last insert (`sqlite3_last_insert_rowid`).
    A new connection has 0 for each. The record of version 7 keeps them as the start of the
    migration (`conformance.record_counters`)."""
    library, handle = connection.library, connection.handle
    return {"changes": library.sqlite3_changes64(handle), "totalChanges": library.sqlite3_total_changes64(handle),
            "lastInsertRowid": library.sqlite3_last_insert_rowid(handle)}
