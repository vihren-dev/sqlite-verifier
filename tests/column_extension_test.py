"""Check value-based column extension, old-row preservation and the new projection."""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

CHECKS = """
import Belay.Sqlite
open Belay.Sqlite

def oldColumn : CatalogColumn := { name := "old", declaredType := some "BLOB" }
def addedColumn : CatalogColumn := { name := "added", declaredType := some "INTEGER" }
def textColumn : CatalogColumn := { name := "label", declaredType := some "TEXT" }
def original : Table where
  shape := { columns := [oldColumn], uniqueKeys := [[0]] }
  rows := [{ rowid := 7, values := [.text [111]] }, { rowid := 3, values := [.blob [0, 255]] }]
def extended : Table := original.appendColumns [(addedColumn, .text [55]), (textColumn, .integer 8)]
#guard extended.rows.map Row.values ==
  [[.text [111], .integer 7, .text [56]], [.blob [0, 255], .integer 7, .text [56]]]
#guard extended.rows.map Row.rowid == [7, 3]
#guard extended.shape.uniqueKeys == [[0]]
#guard extended.project ["old"] == original.project ["old"]
#guard extended.project ["added"] == [(7, [some (.integer 7)]), (3, [some (.integer 7)])]
#guard extended != original.appendColumns [(addedColumn, .integer 9), (textColumn, .integer 8)]
#guard (original.appendColumns []).rows == original.rows
#guard (({ original with rows := [] }).appendColumns [(addedColumn, .integer 7)]).rows.isEmpty

example (table : Table) (valid : table.Valid) (columns : List (CatalogColumn × Value)) :
    (table.appendColumns columns).Valid := valid.appendColumns
example (table : Table) (first second : List (CatalogColumn × Value)) :
    (table.appendColumns first).appendColumns second = table.appendColumns (first ++ second) :=
  table.appendColumns_append first second
example (table : Table) (column : CatalogColumn) (value : Value)
    (width : ∀ row ∈ table.rows, row.values.length = table.shape.columns.length)
    (fresh : columnPosition table.shape.columns column.name = none) :
    (table.appendColumns [(column, value)]).project [column.name] =
      constantExtension (storeValue column.affinity value) (table.project ["old"]) :=
  Table.project_newColumn value width fresh
"""


def test_value_extension_preserves_old_rows(tmp_path: Path, lean_sysroot: Path,
        lean_libraries: tuple[Path, Path]) -> None:
    """Table.appendColumns applies affinity and its kernel proofs preserve rows and both projections."""
    compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
