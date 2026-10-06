import StructuralCodec
import VerifierConformance.Case

/-! Conformance-case transport. The structural codecs for model types live in
`StructuralCodec`, shared with ADR 0003's bundle checker. These codecs are transport,
not a proof oracle. The pure checker has no JSON dependency. -/

namespace SqliteVerifier

deriving instance Lean.FromJson, Lean.ToJson for Conformance.NativeObservation,
  Conformance.StatementOutput, Conformance.OutputGroup, Conformance.NativeOutput
deriving instance Lean.FromJson for Conformance.Case

/-- Preserve v1 transport exactly while adding output fields only to version two. -/
instance : Lean.ToJson Conformance.Case where
  toJson c := Lean.Json.mkObj ([
    ("version", Lean.toJson c.version), ("schemaSql", Lean.toJson c.schemaSql),
    ("migrationSql", Lean.toJson c.migrationSql), ("schema", Lean.toJson c.schema),
    ("initial", Lean.toJson c.initial), ("script", Lean.toJson c.script),
    ("nativeTrace", Lean.toJson c.nativeTrace), ("requirements", Lean.toJson c.requirements),
    ("provenance", Lean.toJson c.provenance)] ++ if c.version == 2 then
      [("parameters", Lean.toJson c.parameters), ("outputs", Lean.toJson c.outputs)] else [])

namespace Conformance

/-- Decode without silently accepting unsupported versions or malformed finite fixtures. -/
def decodeCase (json : Lean.Json) : Except String Case := do
  let version : Nat ← Lean.fromJson? (← json.getObjVal? "version")
  let json := if version == 1 then ["parameters", "outputs"].foldl (fun object key =>
    match object.getObjVal? key with
    | .ok _ => object
    | .error _ => object.setObjVal! key (Lean.Json.arr #[])) json else json
  let c : Case ← Lean.fromJson? json
  unless c.version == 1 || c.version == 2 do throw "unsupported conformance case version"
  unless !(c.nativeTrace.isEmpty) do throw "missing initial native observation"
  for tables in c.initial :: c.nativeTrace.flatMap (fun n => [n.visible, n.persisted]) do
    unless (tables.map Prod.fst).eraseDups.length == tables.length do
      throw "duplicate table name"
    for (_, table) in tables do
      unless (table.rows.map Row.rowid).eraseDups.length == table.rows.length do
        throw "duplicate physical rowid"
      for row in table.rows do
        unless LiteralData.boundedInteger row.rowid && row.values.length == table.columns.length do
          throw "invalid physical rowid or row width"
  for n in c.nativeTrace do
    unless n.extendedCode % 256 == n.primaryCode do throw "inconsistent SQLite result codes"
  if c.version == 1 then
    unless c.outputs.isEmpty && c.parameters.isEmpty do throw "outputs require version two"
  else
    unless c.outputs.length + 1 == c.nativeTrace.length &&
        c.parameters.length == c.outputs.length do throw "output/parameter trace length mismatch"
    for output in c.outputs do
      unless matchesOutput output.result output.result output.groups do
        throw "invalid native output shape or groups"
  return c

end Conformance
end SqliteVerifier
