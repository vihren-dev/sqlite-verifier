"""Current kernel terms reject metadata drift and preserve version-one transport."""

import json
import os
from pathlib import Path

import pytest

from belay.sqlite.quoted_text import quoted_string as lean_string
from belay.sqlite.structural import Json
from tests.runtime_support import run_command

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

SHAPE_CHECKS = """
import Belay.Sqlite
open Belay.Sqlite
def idColumn : Column := { name := "id", affinity := .integer, declaredType := .bigInt, notNull := true }
def stamp : Column := { name := "stamp", affinity := .numeric, defaultValue := some .currentTimestamp }
def data : Column := { name := "data", affinity := .blob }
def shape : TableShape := { columns := [idColumn, stamp, data], properties := {
  primaryKey := ["id"], uniqueKeys := [["stamp"], ["id", "data"]],
  indexes := [{ name := "by_stamp", columns := ["stamp", "id"], unique := true }] } }
def schema : Schema := [{ name := "items", shape := shape }]
def stored (candidate : TableShape) : Database :=
  schema.emptyDatabase.set "items" { shape := candidate, rows := [] }
theorem schema_valid : schema.Valid := by
  simp [schema, Schema.Valid]; decide +kernel
theorem original_conforms : Conforms schema (stored shape) := by
  exact (schema.emptyDatabase_conforms schema_valid).replaceRows
    (old := { shape := shape, rows := [] }) (name := "items") (by rfl) (by rfl)
    ⟨by decide +kernel, by simp, by simp⟩
theorem shape_rejected (candidate : TableShape) (different : candidate ≠ shape) :
    ¬Conforms schema (stored candidate) := by
  intro conforms
  have equal := conforms.shape (show stored candidate "items" =
    some { shape := candidate, rows := [] } by simp [stored, Database.set])
  have same : shape = candidate := by simpa [Schema.lookupShape, schema] using equal
  exact different same.symm
def alternatives : List TableShape := [
  { shape with columns := shape.columns.reverse },
  { shape with columns := [{ idColumn with name := "other" }, stamp, data] },
  { shape with columns := [{ idColumn with declaredType := .canonical }, stamp, data] },
  { shape with columns := [{ idColumn with notNull := false }, stamp, data] },
  { shape with columns := [idColumn, { stamp with defaultValue := none }, data] },
  { shape with columns := [idColumn, stamp, { data with affinity := .text }] },
  { shape with properties.primaryKey := [] },
  { shape with properties.uniqueKeys := shape.properties.uniqueKeys.reverse },
  { shape with properties.indexes := [] },
  { shape with properties.indexes := [{ name := "other", columns := ["stamp", "id"], unique := true }] },
  { shape with properties.indexes := [{ name := "by_stamp", columns := ["id", "stamp"], unique := true }] },
  { shape with properties.indexes := [{ name := "by_stamp", columns := ["stamp", "id"] }] }]
theorem all_changes_rejected : ∀ candidate ∈ alternatives,
    ¬Conforms schema (stored candidate) := by
  intro candidate member
  apply shape_rejected
  simp only [alternatives, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    decide +kernel
example : ¬Conforms schema (fun _ => none) := by
  intro conforms
  have equal := (conforms.2 "items").1
  simp [Schema.lookupShape, schema] at equal
example : ¬Schema.Valid (schema ++ schema) := by simp [schema, Schema.Valid]
example : schema.lookupShape "items" = some shape := rfl
example : schema.lookup "items" = some shape.columns := rfl
example : schema.lookupProperties "items" = some shape.properties := rfl
example : Schema.lookupShape [] "items" = none := rfl
#print axioms original_conforms
#print axioms all_changes_rejected
"""

GOLDEN: dict[str, Json] = {
    "columns": [
        {"name": "id", "affinity": "integer", "declaredType": "bigInt", "notNull": True, "defaultValue": None},
        {"name": "stamp", "affinity": "numeric", "declaredType": "timestamp", "notNull": False,
         "defaultValue": "currentTimestamp"},
        {"name": "data", "affinity": "blob", "declaredType": "untyped", "notNull": False, "defaultValue": None}],
    "properties": {"primaryKey": ["id"], "uniqueKeys": [["stamp"], ["id", "data"]],
                   "indexes": [{"name": "by_λ", "columns": ["stamp", "id"], "unique": True}]},
    "rows": [
        {"rowid": -4, "values": [{"integer": {"value": -(2**63)}},
                                   {"real": {"bits": "9223372036854775808"}}, {"text": {"bytes": [0, 255]}}]},
        {"rowid": 2**63-1, "values": ["null", {"real": {"bits": "9218868437227405312"}}, {"blob": {"bytes": []}}]},
        {"rowid": 0, "values": [{"integer": {"value": 2**63-1}}, {"text": {"bytes": [206, 187]}},
                                  {"blob": {"bytes": [0, 255]}}]}]}


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
    """Model Conforms rejects twelve metadata changes despite unchanged empty rows."""
    compile_checks(SHAPE_CHECKS, tmp_path, lean_sysroot, lean_libraries)


def test_flat_codec_golden(tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Our codec preserves flat metadata and cells while packing the shared shape."""
    schema: dict[str, Json] = {"name": "items", "columns": GOLDEN["columns"], "properties": GOLDEN["properties"]}
    invalid: list[dict[str, Json]] = [
        {key: value for key, value in GOLDEN.items() if key != "properties"},
        {key: value for key, value in GOLDEN.items() if key != "columns"},
        {**GOLDEN, "properties": []}, {**GOLDEN, "columns": "wrong"},
        {**GOLDEN, "rows": [{"rowid": 0, "values": [{"blob": {"bytes": [256]}}]}]}]
    invalid_terms = ", ".join(lean_string(json.dumps(record)) for record in invalid)
    source = "import Belay.Sqlite.Codec\n"
    source += f"""
open Belay.Sqlite Lean
def goldenTable := {lean_string(json.dumps(GOLDEN))}
def goldenSchema := {lean_string(json.dumps(schema))}
def checkGolden : IO Unit := do
  let input ← IO.ofExcept (Json.parse goldenTable)
  let table : Table ← IO.ofExcept (fromJson? input)
  unless toJson table == input && (toJson table).compress == input.compress do throw (IO.userError "table golden changed")
  let entryInput ← IO.ofExcept (Json.parse goldenSchema)
  let entry : TableSchema ← IO.ofExcept (fromJson? entryInput)
  unless toJson entry == entryInput && (toJson entry).compress == entryInput.compress do throw (IO.userError "schema golden changed")
  unless entry.name == "items" && table.shape == entry.shape do
    throw (IO.userError "emitter and shared codec disagree")
  for text in [{invalid_terms}] do
    let invalid ← IO.ofExcept (Json.parse text)
    match (fromJson? invalid : Except String Table) with
    | .ok _ => throw (IO.userError "corrupt metadata or byte accepted")
    | .error _ => pure ()
  IO.println "SHARED_SHAPE_CODEC_OK"
#eval checkGolden
"""
    assert "SHARED_SHAPE_CODEC_OK" in compile_checks(source, tmp_path, lean_sysroot, lean_libraries)


@pytest.mark.parametrize("name", ["Table.columns", "Table.properties", "TableSchema.columns", "TableSchema.properties"])
def test_retired_stored_fields_absent(name: str, tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """The compiler rejects removed duplicated fields; no compatibility alias exists."""
    source = tmp_path / "RemovedShapeField.lean"
    source.write_text(f"import Belay.Sqlite\n#check Belay.Sqlite.{name}\n")
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
        timeout=10, environment={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_libraries))})
    assert result.returncode != 0 and "error(lean.unknownIdentifier)" in result.stdout, result.diagnostic()
