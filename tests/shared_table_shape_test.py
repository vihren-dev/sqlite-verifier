"""The table shape is the catalog entry: conformance rejects drift, and old shape types are gone.

`Belay.Sqlite.Conforms` requires every stored table's shape to equal its catalog
entry under the profile (`Model.lean`); the codec transports rows and values
(`Codec.lean`). The replaced model types of ADR 0008 must not exist.
"""

import json
import os
from pathlib import Path

import pytest

from belay.sqlite.located import Json
from belay.sqlite.quoted_text import quoted_string as lean_string
from tests.runtime_support import run_command

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

SHAPE_CHECKS = """
import Belay.Sqlite
open Belay.Sqlite
def idColumn : CatalogColumn := { name := "id", declaredType := some "BIGINT", notNull := true }
def stamp : CatalogColumn :=
  { name := "stamp", declaredType := some "TIMESTAMP", defaultValue := some ⟨.currentTime "CURRENT_TIMESTAMP", "CURRENT_TIMESTAMP"⟩ }
def data : CatalogColumn := { name := "data", declaredType := none }
def shape : CatalogTable := { columns := [idColumn, stamp, data], primaryKey := [0], uniqueKeys := [[1], [0, 2]] }
def catalog : Catalog := [{ name := "items", entry := .table shape },
  { name := "by_stamp", entry := .index { table := 0, columns := [1, 0], unique := true } }]
def profile : Profile := Profile.documented "3.51.0" "build"
def stored (candidate : CatalogTable) : Database :=
  catalog.emptyDatabase.set 0 { shape := candidate, rows := [] }
theorem catalog_valid : catalog.Valid profile.limits := by decide +kernel
theorem original_conforms : Conforms profile catalog (stored shape) :=
  (Catalog.emptyDatabase_conforms catalog_valid).replaceRows
    (old := { shape := shape, rows := [] }) (position := 0) (by decide +kernel) (by rfl) ⟨by simp, by simp⟩
theorem shape_rejected (candidate : CatalogTable) (different : candidate ≠ shape) :
    ¬Conforms profile catalog (stored candidate) := by
  intro conforms
  have equal := conforms.shape (show stored candidate 0 = some { shape := candidate, rows := [] } by
    simp [stored, Database.set])
  have same : shape = candidate := by simpa [Catalog.tableAt, catalog] using equal
  exact different same.symm
def alternatives : List CatalogTable := [
  { shape with columns := shape.columns.reverse },
  { shape with columns := [{ idColumn with name := "other" }, stamp, data] },
  { shape with columns := [{ idColumn with name := "ID" }, stamp, data] },
  { shape with columns := [{ idColumn with declaredType := some "INTEGER" }, stamp, data] },
  { shape with columns := [{ idColumn with notNull := false }, stamp, data] },
  { shape with columns := [idColumn, { stamp with defaultValue := none }, data] },
  { shape with columns := [idColumn, stamp, { data with declaredType := some "TEXT" }] },
  { shape with primaryKey := [] },
  { shape with uniqueKeys := shape.uniqueKeys.reverse },
  { shape with rowidAlias := some 0 }]
theorem all_changes_rejected : ∀ candidate ∈ alternatives,
    ¬Conforms profile catalog (stored candidate) := by
  intro candidate member
  apply shape_rejected
  simp only [alternatives, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    decide +kernel
example : ¬Conforms profile catalog (fun _ => none) := by
  intro conforms
  have equal := (conforms.2 0).1
  simp [Catalog.tableAt, catalog] at equal
#guard !(catalog ++ catalog).supported profile.limits
example : catalog.tableAt 0 = some shape := rfl
example : catalog.tableAt 1 = none := rfl
example : Catalog.tableAt [] 0 = none := rfl
#print axioms original_conforms
#print axioms all_changes_rejected
"""

GOLDEN: list[Json] = [
    {"rowid": -4, "values": [{"integer": {"value": -(2**63)}},
                             {"real": {"bits": "9223372036854775808"}}, {"text": {"bytes": [0, 255]}}]},
    {"rowid": 2**63-1, "values": ["null", {"real": {"bits": "9218868437227405312"}}, {"blob": {"bytes": []}}]},
    {"rowid": 0, "values": [{"integer": {"value": 2**63-1}}, {"text": {"bytes": [206, 187]}},
                            {"blob": {"bytes": [0, 255]}}]}]


def compile_checks(source: str, directory: Path, sysroot: Path, libraries: tuple[Path, Path]) -> str:
    """Compile and execute fresh codec checks through the selected current library."""
    path = directory / "ShapeChecks.lean"
    path.write_text(source)
    result = run_command([str(sysroot / "bin/lean"), str(path)], cwd=directory,
        timeout=15, environment={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, libraries))})
    assert result.returncode == 0, result.diagnostic()
    assert all(name not in result.stdout for name in ("sorryAx", "ofReduceBool", "_native")), result.stdout
    return result.stdout


def test_whole_shape_conformance(tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Model Conforms rejects ten metadata changes despite unchanged empty rows."""
    compile_checks(SHAPE_CHECKS, tmp_path, lean_sysroot, lean_libraries)


def test_row_codec_golden(tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Our codec preserves every row, rowid and typed cell, and refuses a byte above 255."""
    invalid = [{"rowid": 0, "values": [{"blob": {"bytes": [256]}}]}, {"rowid": 0}, {"values": []}]
    invalid_terms = ", ".join(lean_string(json.dumps(record)) for record in invalid)
    source = "import Belay.Sqlite.Codec\n"
    source += f"""
open Belay.Sqlite Lean
def golden := {lean_string(json.dumps(GOLDEN))}
def checkGolden : IO Unit := do
  let input ← IO.ofExcept (Json.parse golden)
  let rows : List Row ← IO.ofExcept (fromJson? input)
  unless toJson rows == input && (toJson rows).compress == input.compress do throw (IO.userError "row golden changed")
  for text in [{invalid_terms}] do
    let invalid ← IO.ofExcept (Json.parse text)
    match (fromJson? invalid : Except String Row) with
    | .ok _ => throw (IO.userError "corrupt row accepted")
    | .error _ => pure ()
  IO.println "ROW_CODEC_OK"
#eval checkGolden
"""
    assert "ROW_CODEC_OK" in compile_checks(source, tmp_path, lean_sysroot, lean_libraries)


@pytest.mark.parametrize("name", ["Schema", "TableSchema", "TableShape", "TableProperties", "IndexDefinition",
                                  "DeclaredType", "Column", "maximumColumns", "ExecutionProfile", "Statement",
                                  "supportedColumns", "GeneratedInputs", "Table.properties"])
def test_replaced_model_names_absent(name: str, tmp_path: Path, lean_sysroot: Path,
                                     lean_libraries: tuple[Path, Path]) -> None:
    """The compiler rejects each model name that ADR 0008 replaced; no compatibility alias exists."""
    source = tmp_path / "ReplacedName.lean"
    source.write_text(f"import Belay.Sqlite\nimport Belay.Sqlite.Codec.Resolution\n#check Belay.Sqlite.{name}\n")
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
        timeout=10, environment={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_libraries))})
    assert result.returncode != 0 and "error(lean.unknownIdentifier)" in result.stdout, result.diagnostic()
