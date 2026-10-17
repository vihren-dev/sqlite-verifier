import Belay.Sqlite.Codec

set_option doc.verso true

/-! JSON transport and closed kernel terms for statement syntax, catalogs and
resolved statements, and the structural record of a schema and a script. A
program that maps SQL text to statements writes the record, and a program that
resolves the statements reads it. -/

namespace Belay.Sqlite

deriving instance Lean.FromJson, Lean.ToJson for Comparison, ArithmeticOperator
deriving instance Lean.FromJson, Lean.ToJson for ConflictAlgorithm
deriving instance Lean.FromJson, Lean.ToJson for Syntax.Expr, Syntax.DefaultExpression, Syntax.ColumnConstraint
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ResultColumn, Syntax.OrderTerm
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ColumnDefinition, Syntax.TableConstraint
deriving instance Lean.FromJson, Lean.ToJson for Syntax.TableReference, Syntax.Join
deriving instance Lean.FromJson, Lean.ToJson for Syntax.ConflictAction, Syntax.ConflictClause
deriving instance Lean.FromJson, Lean.ToJson for Syntax.Write
deriving instance Lean.FromJson, Lean.ToJson for Syntax.Statement
deriving instance Lean.ToJson for PrepareError

/-- A model restriction as JSON: the statement index, the path, the message that users
read as {lit}`reason`, and the stable id of its kind as {lit}`restriction`. -/
instance : Lean.ToJson Restriction where
  toJson restriction := Lean.Json.mkObj [("statement", Lean.toJson restriction.statement),
    ("path", Lean.toJson restriction.path), ("reason", Lean.toJson restriction.reason),
    ("restriction", Lean.toJson restriction.kind.id)]

deriving instance Lean.ToJson for ScriptIssue

-- One command per type: a combined `deriving instance` treats its types as one group.
deriving instance Lean.ToExpr for Comparison
deriving instance Lean.ToExpr for ArithmeticOperator
deriving instance Lean.ToExpr for Affinity
deriving instance Lean.ToExpr for ConflictAlgorithm
deriving instance Lean.ToExpr for Syntax.Expr
deriving instance Lean.ToExpr for Syntax.ResultColumn
deriving instance Lean.ToExpr for Syntax.OrderTerm
deriving instance Lean.ToExpr for Syntax.DefaultExpression
deriving instance Lean.ToExpr for Syntax.ColumnConstraint
deriving instance Lean.ToExpr for Syntax.ColumnDefinition
deriving instance Lean.ToExpr for Syntax.TableConstraint
deriving instance Lean.ToExpr for Syntax.TableReference
deriving instance Lean.ToExpr for Syntax.Join
deriving instance Lean.ToExpr for Syntax.ConflictAction
deriving instance Lean.ToExpr for Syntax.ConflictClause
deriving instance Lean.ToExpr for Syntax.Write
deriving instance Lean.ToExpr for Syntax.Statement
deriving instance Lean.ToExpr for Limits
deriving instance Lean.ToExpr for Profile
deriving instance Lean.ToExpr for CatalogColumn
deriving instance Lean.ToExpr for CatalogTable
deriving instance Lean.ToExpr for CatalogIndex
deriving instance Lean.ToExpr for CatalogEntry
deriving instance Lean.ToExpr for CatalogObject
deriving instance Lean.ToExpr for PrepareError
deriving instance Lean.ToExpr for Resolved.JsonFunction
deriving instance Lean.ToExpr for TimeKeyword
deriving instance Lean.ToExpr for Resolved.Expr, Resolved.Arguments
deriving instance Lean.ToExpr for Resolved.Aggregate
deriving instance Lean.ToExpr for Resolved.Output
deriving instance Lean.ToExpr for Resolved.SortKey
deriving instance Lean.ToExpr for Resolved.JoinKind
deriving instance Lean.ToExpr for Resolved.Join
deriving instance Lean.ToExpr for Resolved.EachSource
deriving instance Lean.ToExpr for Resolved.Query
deriving instance Lean.ToExpr for Resolved.ConflictAction
deriving instance Lean.ToExpr for Resolved.ConflictClause
deriving instance Lean.ToExpr for Resolved.ConflictPolicy
deriving instance Lean.ToExpr for Resolved.ClockCell
deriving instance Lean.ToExpr for Resolved.Statement

/-- The supported version of {lit}`ScriptRecord`, the structural record of a schema
and a script: {assert}`scriptRecordVersion = 3`. Version 3 retains each default's
source spelling. Earlier versions do not carry this metadata. -/
def scriptRecordVersion : Nat := 3

/-- The structural record of a schema and a script: the SQLite release and build of
the profile, and the schema and script statements as written. Use an empty schema
list for an empty starting catalog. -/
structure ScriptRecord where
  /-- The wire format version; supported records use {name}`scriptRecordVersion`. -/
  version : Nat
  /-- The SQLite release, for example {lit}`3.51.0`. -/
  release : String
  /-- The {lit}`sqlite_source_id()` of the build. -/
  sourceId : String
  /-- The schema statements as written. -/
  schema : List Syntax.Statement
  /-- The script statements as written. -/
  script : List Syntax.Statement
  deriving Lean.FromJson, Lean.ToJson

/-- The profile of a record: the documented defaults of its release and build,
until a measured profile can be given. -/
def ScriptRecord.profile (record : ScriptRecord) : Profile :=
  Profile.documented record.release record.sourceId

/-- Resolve the schema and the script of a record. -/
def ScriptRecord.resolve (record : ScriptRecord) : Except ScriptIssue ResolvedScript :=
  resolveSchemaAndScript record.profile record.schema record.script

/-- Decode a record, and refuse versions other than {name}`scriptRecordVersion`. -/
def decodeScriptRecord (json : Lean.Json) : Except String ScriptRecord := do
  let record : ScriptRecord ← Lean.fromJson? json
  unless record.version == scriptRecordVersion do
    throw s!"script record version {record.version} is unsupported; only version {scriptRecordVersion} is supported. Regenerate the record with a matching frontend."
  return record

end Belay.Sqlite
