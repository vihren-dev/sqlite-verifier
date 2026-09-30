import StructuralCodec
import VerifierConformance.Case

/-! Conformance-case transport. The structural codecs for model types live in
`StructuralCodec`, shared with ADR 0003's bundle checker. These codecs are transport,
not a proof oracle. The pure checker has no JSON dependency. -/

namespace SqliteVerifier

deriving instance Lean.FromJson, Lean.ToJson for Conformance.NativeObservation, Conformance.Case

namespace Conformance

/-- Decode without silently accepting unsupported versions or malformed finite fixtures. -/
def decodeCase (json : Lean.Json) : Except String Case := do
  let c : Case ← Lean.fromJson? json
  unless c.version == 1 do throw "unsupported conformance case version"
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
  return c

end Conformance
end SqliteVerifier
