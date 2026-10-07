import Lean
import Belay.Sqlite

set_option doc.verso true

/-! Version-one JSON transport for SQLite model values. Decoding constructs data;
the kernel still checks every proposition about those values.

This module imports {module}`Lean`; the {module}`Belay.Sqlite` core does not. -/

namespace Belay.Sqlite

/-- Byte transport rejects overflow instead of wrapping corrupt TEXT/BLOB data. -/
instance : Lean.FromJson UInt8 where
  fromJson? json := do
    let value ← json.getNat?
    if value < 256 then return UInt8.ofNat value else throw "byte outside 0..255"

/-- Encode bytes as JSON integers. REAL payloads use UInt64 decimal strings. -/
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

/-- A versioned profile, schema transition and script record. Use version 1;
empty schemas and scripts remain ordinary model values. This transport does
not define application declarations or establish verification conditions. -/
structure GeneratedInputs where
  /-- The wire format version; supported records use 1. -/
  version : Nat
  /-- Execution profile supplied by the caller, independent of runtime discovery. -/
  profile : ExecutionProfile
  /-- Starting schema; use an empty list for no declared tables. -/
  schema : Schema
  /-- Resulting schema supplied by the frontend; it is not certified by decoding. -/
  nextSchema : Schema
  /-- Ordered statements; an empty list denotes no statements. -/
  script : List Statement
  deriving Lean.FromJson, Lean.ToJson

/-- Decode a generated-inputs record, rejecting other versions. -/
def decodeGeneratedInputs (json : Lean.Json) : Except String GeneratedInputs := do
  let inputs : GeneratedInputs ← Lean.fromJson? json
  unless inputs.version == 1 do throw "unsupported generated-inputs version"
  return inputs

end Belay.Sqlite
