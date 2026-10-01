import Lean
import SqliteVerifier

/-! Version-one structural encoding of frontend results, shared by the conformance
runner (ADR 0004) and the bundle checker (ADR 0003 P3). See
`docs/conformance-format-v1.md`. These codecs are transport, not a proof oracle:
every declaration built from decoded data is still checked by the kernel.

This module imports `Lean`; the `SqliteVerifier` library deliberately does not. -/

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
deriving instance Lean.FromJson, Lean.ToJson for ExecutionProfile

-- Decoded values become closed kernel terms without elaborating generated source.
-- One command per type: a combined `deriving instance` treats its types as one group.
deriving instance Lean.ToExpr for Affinity
deriving instance Lean.ToExpr for DeclaredType
deriving instance Lean.ToExpr for ColumnDefault
deriving instance Lean.ToExpr for Column
deriving instance Lean.ToExpr for IndexDefinition
deriving instance Lean.ToExpr for TableProperties
deriving instance Lean.ToExpr for Value
deriving instance Lean.ToExpr for TableSchema
deriving instance Lean.ToExpr for Statement
deriving instance Lean.ToExpr for ExecutionProfile

/-- The frontend's result for one request: what `SchemaInputs` and `SqlInputs` define. -/
structure GeneratedInputs where
  version : Nat
  profile : ExecutionProfile
  schema : Schema
  nextSchema : Schema
  script : List Statement
  deriving Lean.FromJson, Lean.ToJson

/-- Decode a generated-inputs record, rejecting other versions. -/
def decodeGeneratedInputs (json : Lean.Json) : Except String GeneratedInputs := do
  let inputs : GeneratedInputs ← Lean.fromJson? json
  unless inputs.version == 1 do throw "unsupported generated-inputs version"
  return inputs

end SqliteVerifier
