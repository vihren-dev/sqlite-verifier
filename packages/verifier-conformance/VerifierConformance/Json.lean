import Belay.Sqlite.Model.Codec.Resolution
import VerifierConformance.Case

/-! Conformance-case transport. The structural codecs for model types live in
`Belay.Sqlite.Model.Codec`, shared with ADR 0003's bundle checker. These codecs are transport,
not a proof oracle. The pure checker has no JSON dependency. -/

open Belay.Sqlite.Model

namespace Belay.Sqlite.Model

deriving instance Lean.FromJson, Lean.ToJson for Limits
/-- A profile as JSON, with {lit}`foreignKeys` and {lit}`recursiveTriggers` only for a profile
that turns the setting on, so the records of other profiles keep their form. -/
instance : Lean.ToJson Profile where
  toJson profile := Lean.Json.mkObj ([("release", Lean.toJson profile.release),
      ("sourceId", Lean.toJson profile.sourceId), ("limits", Lean.toJson profile.limits),
      ("dqsDml", Lean.toJson profile.dqsDml), ("dqsDdl", Lean.toJson profile.dqsDdl)] ++
    (if profile.foreignKeys then [("foreignKeys", Lean.toJson true)] else []) ++
    (if profile.recursiveTriggers then [("recursiveTriggers", Lean.toJson true)] else []))

/-- Read a profile ({name}`Profile`); a missing {lit}`foreignKeys` or {lit}`recursiveTriggers`
is a profile with that setting off. -/
instance : Lean.FromJson Profile where
  fromJson? json := do
    let foreignKeys : Bool := (json.getObjValAs? Bool "foreignKeys").toOption.getD false
    let recursiveTriggers : Bool := (json.getObjValAs? Bool "recursiveTriggers").toOption.getD false
    return { release := ← json.getObjValAs? String "release", sourceId := ← json.getObjValAs? String "sourceId",
             limits := ← json.getObjValAs? Limits "limits", dqsDml := ← json.getObjValAs? Bool "dqsDml",
             dqsDdl := ← json.getObjValAs? Bool "dqsDdl", foreignKeys, recursiveTriggers }
deriving instance Lean.FromJson, Lean.ToJson for Conformance.ErrorPhase
/-- A native column as JSON, with {lit}`hidden` only for a generated column, so the records of
other columns keep their form. -/
instance : Lean.ToJson Conformance.NativeColumn where
  toJson column := Lean.Json.mkObj ([("name", Lean.toJson column.name),
      ("declaredType", Lean.toJson column.declaredType), ("notNull", Lean.toJson column.notNull),
      ("defaultValue", Lean.toJson column.defaultValue)] ++
    (if column.hidden == 0 then [] else [("hidden", Lean.toJson column.hidden)]))

/-- Read a native column ({name}`Conformance.NativeColumn`); a missing {lit}`hidden` is an
ordinary column. -/
instance : Lean.FromJson Conformance.NativeColumn where
  fromJson? json := do
    let hidden : Nat := (json.getObjValAs? Nat "hidden").toOption.getD 0
    return { name := ← json.getObjValAs? Identifier "name", declaredType := ← json.getObjValAs? String "declaredType",
             notNull := ← json.getObjValAs? Bool "notNull",
             defaultValue := ← json.getObjValAs? (Option String) "defaultValue", hidden }

/-- A native index as JSON: {lit}`name`, {lit}`columns` (a number for a column key, null for an
expression), {lit}`unique`, and {lit}`descending`, {lit}`partial` and {lit}`collations` only when
an index has a descending term, is partial or has a term that is not {lit}`BINARY`, so the
records of indexes without them keep their form. -/
instance : Lean.ToJson Conformance.NativeIndex where
  toJson index := Lean.Json.mkObj ([("name", Lean.toJson index.name), ("columns", Lean.toJson index.columns),
      ("unique", Lean.toJson index.unique)] ++
    (if index.descending.isEmpty then [] else [("descending", Lean.toJson index.descending)]) ++
    (if index.isPartial then [("partial", Lean.toJson true)] else []) ++
    (if index.collations.isEmpty then [] else [("collations", Lean.toJson index.collations)]))

/-- Read a native index ({name}`Conformance.NativeIndex`); a missing {lit}`descending` is every
term ascending, a missing {lit}`partial` is a full index, and a missing {lit}`collations` is
every term {lit}`BINARY`. -/
instance : Lean.FromJson Conformance.NativeIndex where
  fromJson? json := do
    let descending : List Bool ← (json.getObjValAs? (List Bool) "descending").toOption.getD [] |> pure
    let isPartial : Bool ← (json.getObjValAs? Bool "partial").toOption.getD false |> pure
    let collations : List String ← (json.getObjValAs? (List String) "collations").toOption.getD [] |> pure
    return { name := ← json.getObjValAs? Identifier "name", columns := ← json.getObjValAs? (List (Option Nat)) "columns",
             unique := ← json.getObjValAs? Bool "unique", descending := Conformance.sortOrders descending, isPartial,
             collations := Conformance.collationNames collations }

/-- A native table as JSON, with {lit}`withoutRowid` only for a {lit}`WITHOUT ROWID` table, so the
records of other tables keep their form. -/
instance : Lean.ToJson Conformance.NativeTable where
  toJson table := Lean.Json.mkObj ([("name", Lean.toJson table.name), ("columns", Lean.toJson table.columns),
      ("primaryKey", Lean.toJson table.primaryKey), ("uniqueKeys", Lean.toJson table.uniqueKeys),
      ("indexes", Lean.toJson table.indexes), ("rows", Lean.toJson table.rows)] ++
    (if table.withoutRowid then [("withoutRowid", Lean.toJson true)] else []))

/-- Read a native table ({name}`Conformance.NativeTable`); a missing {lit}`withoutRowid` is a
table with a rowid. -/
instance : Lean.FromJson Conformance.NativeTable where
  fromJson? json := do
    let withoutRowid : Bool := (json.getObjValAs? Bool "withoutRowid").toOption.getD false
    return { name := ← json.getObjValAs? Identifier "name", columns := ← json.getObjValAs? _ "columns",
             primaryKey := ← json.getObjValAs? _ "primaryKey", uniqueKeys := ← json.getObjValAs? _ "uniqueKeys",
             indexes := ← json.getObjValAs? _ "indexes", rows := ← json.getObjValAs? _ "rows", withoutRowid }

deriving instance Lean.FromJson, Lean.ToJson for Conformance.NativeObservation
deriving instance Lean.FromJson, Lean.ToJson for StatementOutput, Conformance.OutputGroup,
  Conformance.NativeOutput
deriving instance Lean.FromJson, Lean.ToJson for Conformance.Case

namespace Conformance

/-- The supported case version: {assert}`caseVersion = 5`. Version 5 retains default
source spelling in statement syntax. Version 4 lacked that spelling. -/
def caseVersion : Nat := 5

/-- Check one native table: folded-name uniqueness is checked by the caller; here,
distinct bounded rowids, except in a {lit}`WITHOUT ROWID` table, and one cell per column. -/
def checkNativeTable (table : NativeTable) : Except String Unit := do
  unless table.withoutRowid || (table.rows.map Row.rowid).eraseDups.length == table.rows.length do
    throw "duplicate physical rowid"
  for row in table.rows do
    unless LiteralData.boundedInteger row.rowid && row.values.length == table.columns.length do
      throw "invalid physical rowid or row width"

/-- Decode without silently accepting unsupported versions or malformed finite fixtures. -/
def decodeCase (json : Lean.Json) : Except String Case := do
  let c : Case ← Lean.fromJson? json
  unless c.version == caseVersion do throw s!"unsupported conformance case version {c.version}; regenerate the case"
  unless !(c.nativeTrace.isEmpty) do throw "missing initial native observation"
  for tables in c.initial :: c.nativeTrace.flatMap (fun n => [n.visible, n.persisted]) do
    unless (tables.map (·.name.folded)).eraseDups.length == tables.length do
      throw "duplicate table name"
    for table in tables do checkNativeTable table
  for (n, position) in c.nativeTrace.zipIdx do
    unless n.extendedCode % 256 == n.primaryCode do throw "inconsistent SQLite result codes"
    unless n.primaryCode != 0 || n.phase.isNone do
      throw s!"native observation {position} has an error phase but result code 0; record the case again, \
        so that a successful observation has a null phase"
  unless c.clocks.isEmpty || c.clocks.length + 1 == c.nativeTrace.length do
    throw "clock trace length mismatch: give one clock value for each executed statement, or none"
  match c.outputs with
  | none => unless c.parameters.isEmpty do throw "parameters require outputs"
  | some outputs =>
    unless outputs.length + 1 == c.nativeTrace.length && c.parameters.length == outputs.length do
      throw "output/parameter trace length mismatch"
    for output in outputs do
      unless matchesOutput output.result output.result output.groups do
        throw "invalid native output shape or groups"
  return c

end Conformance
end Belay.Sqlite.Model
