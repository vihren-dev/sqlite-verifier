"""Embed every captured metadata/statistics row without erasing physical identity."""
from __future__ import annotations

from typing import cast
from migration_check.sql_model import Table, lean_string
from atuin_cases import Cell, lean_rows, text

NAMES = ("_sqlx_migrations", "history", "sqlite_stat1", "sqlite_stat4")
LABELS = ("Metadata", "History", "Stat1", "Stat4")


def row_literal(rowid: int, cells: list[Cell]) -> str:
    """Rowid and all stored classes come from the concrete native observation."""
    return f"{{ rowid := ({rowid}), values := [" + ",".join(cell.lean() for cell in cells) + "] }"


def metadata_rows(rows: list[dict[str, object]]) -> str:
    """The pinned runner binds integers, UTF-8 text and exact checksum blobs."""
    return "[" + ",".join(row_literal(int(row["rowid"]), [
        Cell("integer", int(row["version"])), text(str(row["description"])),
        text(str(row["installed_on"])), Cell("integer", int(row["success"])),
        Cell("blob", bytes.fromhex(str(row["checksum_hex"]))),
        Cell("integer", int(row["execution_time"]))]) for row in rows) + "]"


def statistics_rows(rows: list[list[int | str]]) -> str:
    """Decode actual typeof/quote/hex triples; unsupported classes fail rather than round."""
    result = []
    for row in rows:
        assert (len(row) - 1) % 3 == 0
        cells = []
        for index in range(1, len(row), 3):
            kind, quoted, raw = row[index:index+3]
            if kind == "null":
                cells.append(Cell("null"))
            elif kind == "integer":
                cells.append(Cell("integer", int(quoted)))
            elif kind in ("text", "blob"):
                cells.append(Cell("text" if kind == "text" else "blob", bytes.fromhex(str(raw))))
            else:
                raise AssertionError(("Unexpected native statistics class", kind))
        result.append(row_literal(int(row[0]), cells))
    return "[" + ",".join(result) + "]"


def table_definitions(prefix: str, schema: tuple[Table, ...], snapshot: dict[str, object],
                      *, after: bool) -> str:
    """Include all four tables; history expectations remain independent of native output."""
    tables = {table.name: table for table in schema}
    assert set(tables) == set(NAMES)
    stats = cast(dict[str, list[list[int | str]]], snapshot["statistics"])
    rows = [metadata_rows(cast(list[dict[str, object]], snapshot["metadata"])),
            lean_rows(3, after=after), statistics_rows(stats["sqlite_stat1"]),
            statistics_rows(stats["sqlite_stat4"])]
    result = []
    for name, label, values in zip(NAMES, LABELS, rows, strict=True):
        result.append(f"def {prefix}{label} : Table :=\n"
            f"  let declaration : TableSchema := {tables[name].lean()}\n"
            f"  {{ columns := declaration.columns, properties := declaration.properties, rows := {values} }}\n"
            f"theorem {prefix}{label}_valid : {prefix}{label}.Valid := by\n"
            f"  simp [Table.Valid, {prefix}{label}, validRowid]\n  decide +kernel\n")
    expression = "none"
    for name, label in reversed(list(zip(NAMES, LABELS, strict=True))):
        expression = f"if name = {lean_string(name)} then some {prefix}{label} else ({expression})"
    result.append(f"def {prefix} : Database := fun name => {expression}\n")
    return "\n".join(result)
