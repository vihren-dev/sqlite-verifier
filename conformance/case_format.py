"""Conformance-side view of the version-one structural JSON.

The encoders live in `belay.sqlite.structural`, shared with the bundle checker.
"""

from belay.sqlite.sql_model import Table
from belay.sqlite.structural import (Cell, Json, cell_wire, column_wire, literal_cell, schema_wire,
                                        statement_wire)

__all__ = ["Cell", "Json", "cell_wire", "column_wire", "literal_cell", "schema_wire", "statement_wire",
           "table_wire"]


def table_wire(table: Table, rows: list[tuple[int, tuple[Cell, ...]]]) -> dict[str, Json]:
    """Attach exact physical rows to the same schema encoding used by the frontend."""
    metadata = schema_wire(table)
    return {"columns": metadata["columns"], "properties": metadata["properties"],
            "rows": [{"rowid": rowid, "values": [cell_wire(cell) for cell in cells]}
                     for rowid, cells in rows]}
