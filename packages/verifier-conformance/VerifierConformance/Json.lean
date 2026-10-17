import Belay.Sqlite.Codec.Resolution
import VerifierConformance.Case

/-! Conformance-case transport. The structural codecs for model types live in
`Belay.Sqlite.Codec`, shared with ADR 0003's bundle checker. These codecs are transport,
not a proof oracle. The pure checker has no JSON dependency. -/

open Belay.Sqlite

namespace Belay.Sqlite

deriving instance Lean.FromJson, Lean.ToJson for Limits, Profile
deriving instance Lean.FromJson, Lean.ToJson for Conformance.ErrorPhase
deriving instance Lean.FromJson, Lean.ToJson for Conformance.NativeColumn, Conformance.NativeIndex,
  Conformance.NativeTable, Conformance.NativeObservation
deriving instance Lean.FromJson, Lean.ToJson for Conformance.StatementOutput, Conformance.OutputGroup,
  Conformance.NativeOutput
deriving instance Lean.FromJson, Lean.ToJson for Conformance.Case

namespace Conformance

/-- The supported case version: {assert}`caseVersion = 5`. Version 5 retains default
source spelling in statement syntax. Version 4 lacked that spelling. -/
def caseVersion : Nat := 5

/-- Check one native table: folded-name uniqueness is checked by the caller; here,
distinct bounded rowids and one cell per column. -/
def checkNativeTable (table : NativeTable) : Except String Unit := do
  unless (table.rows.map Row.rowid).eraseDups.length == table.rows.length do
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
    unless (tables.map (normalizeIdentifier ·.name)).eraseDups.length == tables.length do
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
end Belay.Sqlite
