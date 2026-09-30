import Lean
import VerifierConformance.Case

/-! Version-one structural encoding, shared with ADR 0003's future frontend path.
These codecs are transport, not a proof oracle. The pure checker has no JSON dependency. -/

namespace SqliteVerifier

/-- Byte transport rejects overflow instead of wrapping corrupt TEXT/BLOB data. -/
instance : Lean.FromJson UInt8 where
  fromJson? json := do
    let value ← json.getNat?
    if value < 256 then return UInt8.ofNat value else throw "byte outside 0..255"

/-- Bytes use ordinary JSON integers; REAL payloads use Lean's UInt64 decimal strings. -/
instance : Lean.ToJson UInt8 where
  toJson value := Lean.toJson value.toNat

deriving instance Lean.FromJson, Lean.ToJson for Affinity, DeclaredType, ColumnDefault
deriving instance Lean.FromJson, Lean.ToJson for Column, IndexDefinition, TableProperties
deriving instance Lean.FromJson, Lean.ToJson for Value, Row, Table, TableSchema, Statement
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
