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
deriving instance Lean.FromJson, Lean.ToJson for Value, Row, Statement
deriving instance Lean.FromJson, Lean.ToJson for ExecutionProfile

/-- Decode the version-one flat metadata into one complete shape. Every column
and property field remains required; invalid fields retain their diagnostic path. -/
private def shapeFromJson (typeName : String) (json : Lean.Json) : Except String TableShape := do
  let columns ← Except.mapError (fun message => typeName ++ ".columns: " ++ message)
    (json.getObjValAs? (List Column) "columns")
  let properties ← Except.mapError (fun message => typeName ++ ".properties: " ++ message)
    (json.getObjValAs? TableProperties "properties")
  return { columns, properties }

/-- Encode shared metadata with the existing flat version-one field names. -/
private def shapeFields (shape : TableShape) : List (String × Lean.Json) :=
  [("columns", Lean.toJson shape.columns), ("properties", Lean.toJson shape.properties)]

/-- Decode stored rows and the complete shared shape from version-one transport.
Missing or ill-typed metadata and rows return an error; empty rows remain present. -/
instance : Lean.FromJson Table where
  fromJson? json := do
    let shape ← shapeFromJson "Belay.Sqlite.Table" json
    let rows ← Except.mapError (fun message => "Belay.Sqlite.Table.rows: " ++ message)
      (json.getObjValAs? (List Row) "rows")
    return { shape, rows }

/-- Preserve the original flat columns/rows/properties field order and every
ordered row/cell in version-one records. -/
instance : Lean.ToJson Table where
  toJson table := Lean.Json.mkObj [("columns", Lean.toJson table.shape.columns),
    ("rows", Lean.toJson table.rows), ("properties", Lean.toJson table.shape.properties)]

/-- Decode a named schema entry with the same complete shape as a stored table.
Missing or ill-typed names or metadata return an error. -/
instance : Lean.FromJson TableSchema where
  fromJson? json := do
    let name ← Except.mapError (fun message => "Belay.Sqlite.TableSchema.name: " ++ message)
      (json.getObjValAs? String "name")
    let shape ← shapeFromJson "Belay.Sqlite.TableSchema" json
    return { name, shape }

/-- Preserve flat schema fields, including declaration and index order. -/
instance : Lean.ToJson TableSchema where
  toJson entry := Lean.Json.mkObj (("name", Lean.toJson entry.name) :: shapeFields entry.shape)

-- Decoded values become closed kernel terms without elaborating generated source.
-- One command per type: a combined `deriving instance` treats its types as one group.
deriving instance Lean.ToExpr for Affinity
deriving instance Lean.ToExpr for DeclaredType
deriving instance Lean.ToExpr for ColumnDefault
deriving instance Lean.ToExpr for Column
deriving instance Lean.ToExpr for IndexDefinition
deriving instance Lean.ToExpr for TableProperties
deriving instance Lean.ToExpr for TableShape
deriving instance Lean.ToExpr for Value
deriving instance Lean.ToExpr for TableSchema
deriving instance Lean.ToExpr for Statement
deriving instance Lean.ToExpr for ExecutionProfile

/-- A versioned profile, schema transition and script record. Use version 1;
empty schemas and scripts remain ordinary SQLite model values. The record
transports the starting schema, resulting schema and ordered statements. -/
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
  unless inputs.version == 1 do
    throw s!"generated-inputs version {inputs.version} is unsupported; only version 1 is supported. Regenerate the inputs with a matching frontend."
  return inputs

end Belay.Sqlite
