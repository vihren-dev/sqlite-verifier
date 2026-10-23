import Belay.Sqlite.Model.Codec.SyntaxJson

set_option doc.verso true

/-! JSON transport and closed kernel terms for statement syntax, catalogs and
resolved statements, and the structural record of a schema and a script. A
program that maps SQL text to statements writes the record, and a program that
resolves the statements reads it. -/

namespace Belay.Sqlite.Model

deriving instance Lean.ToJson for ExprError

/-- A prepare error as JSON, in one flat form: an error that names a catalog object as its
own constructor, and an {name}`ExprError` as that error's constructor, so the wire form
does not show the split of the two types. For example, {lit}`no such table: t` is
{lit}`{"noSuchTable": {"name": "t"}}` and {lit}`no such column: a` is
{lit}`{"noSuchColumn": {"name": "a"}}`, the derived form of each constructor. -/
instance : Lean.ToJson PrepareError where
  toJson
    | .tableExists name => Lean.Json.mkObj [("tableExists", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .indexNameUsed name => Lean.Json.mkObj [("indexNameUsed", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .tableNameUsed name => Lean.Json.mkObj [("tableNameUsed", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .indexExists name => Lean.Json.mkObj [("indexExists", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .noSuchTable name => Lean.Json.mkObj [("noSuchTable", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .noSuchIndex name => Lean.Json.mkObj [("noSuchIndex", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .tableMayNotBeDropped name =>
      Lean.Json.mkObj [("tableMayNotBeDropped", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .noSuchReferencedTable name =>
      Lean.Json.mkObj [("noSuchReferencedTable", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .foreignKeyMismatch child parent =>
      Lean.Json.mkObj [("foreignKeyMismatch", Lean.Json.mkObj [("child", Lean.toJson child), ("parent", Lean.toJson parent)])]
    | .noSuchTrigger name => Lean.Json.mkObj [("noSuchTrigger", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .triggerExists name => Lean.Json.mkObj [("triggerExists", Lean.Json.mkObj [("name", Lean.toJson name)])]
    | .expression error => Lean.toJson error

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
deriving instance Lean.ToExpr for CompoundOperator
deriving instance Lean.ToExpr for Affinity
deriving instance Lean.ToExpr for ConflictAlgorithm
deriving instance Lean.ToExpr for Syntax.QuoteKind
deriving instance Lean.ToExpr for Syntax.RaiseKind
deriving instance Lean.ToExpr for Syntax.Expr
deriving instance Lean.ToExpr for Syntax.ResultColumn
deriving instance Lean.ToExpr for Syntax.OrderTerm
deriving instance Lean.ToExpr for Syntax.DefaultExpression
deriving instance Lean.ToExpr for Syntax.ForeignKeyAction
deriving instance Lean.ToExpr for Syntax.ColumnConstraint
deriving instance Lean.ToExpr for Syntax.ColumnDefinition
deriving instance Lean.ToExpr for Syntax.TableConstraint
deriving instance Lean.ToExpr for Syntax.TableReference
deriving instance Lean.ToExpr for Syntax.Join
deriving instance Lean.ToExpr for Syntax.Compound
deriving instance Lean.ToExpr for Syntax.Subquery
deriving instance Lean.ToExpr for Syntax.ConflictAction
deriving instance Lean.ToExpr for Syntax.ConflictClause
deriving instance Lean.ToExpr for Syntax.TableOptions
deriving instance Lean.ToExpr for Syntax.TriggerTime
deriving instance Lean.ToExpr for Syntax.TriggerEvent
deriving instance Lean.ToExpr for Syntax.BodyStatement
deriving instance Lean.ToExpr for Syntax.Statement
deriving instance Lean.ToExpr for Limits
deriving instance Lean.ToExpr for Profile
deriving instance Lean.ToExpr for TimeKeyword
deriving instance Lean.ToExpr for DefaultInsert
deriving instance Lean.ToExpr for DefaultForm
deriving instance Lean.ToExpr for ColumnDefault
deriving instance Lean.ToExpr for Collation
deriving instance Lean.ToExpr for Resolved.JsonFunction
deriving instance Lean.ToExpr for Resolved.DateFunction
deriving instance Lean.ToExpr for Resolved.TrimSide
deriving instance Lean.ToExpr for Resolved.ScalarFunction
deriving instance Lean.ToExpr for Resolved.Expr, Resolved.Arguments
deriving instance Lean.ToExpr for CheckConstraint
deriving instance Lean.ToExpr for ForeignKey
deriving instance Lean.ToExpr for GeneratedColumn
deriving instance Lean.ToExpr for StrictType
deriving instance Lean.ToExpr for CatalogColumn
deriving instance Lean.ToExpr for CatalogTable
deriving instance Lean.ToExpr for KeyTerm
deriving instance Lean.ToExpr for IndexKey
deriving instance Lean.ToExpr for CatalogIndex
deriving instance Lean.ToExpr for CatalogTrigger
deriving instance Lean.ToExpr for CatalogEntry
deriving instance Lean.ToExpr for CatalogObject
deriving instance Lean.ToExpr for Database
deriving instance Lean.ToExpr for ExprError
deriving instance Lean.ToExpr for PrepareError
deriving instance Lean.ToExpr for Resolved.Aggregate
deriving instance Lean.ToExpr for Resolved.Output
deriving instance Lean.ToExpr for Resolved.SortKey
deriving instance Lean.ToExpr for Resolved.SortTerm
deriving instance Lean.ToExpr for Resolved.JoinKind
deriving instance Lean.ToExpr for Resolved.Source
deriving instance Lean.ToExpr for Resolved.QuerySource
deriving instance Lean.ToExpr for Resolved.Compound
deriving instance Lean.ToExpr for Resolved.Query
deriving instance Lean.ToExpr for Resolved.ConflictAction
deriving instance Lean.ToExpr for Resolved.ConflictClause
deriving instance Lean.ToExpr for Resolved.ConflictPolicy
deriving instance Lean.ToExpr for Resolved.Cell
deriving instance Lean.ToExpr for Resolved.TriggerEvent
deriving instance Lean.ToExpr for Resolved.Step
deriving instance Lean.ToExpr for Resolved.Program
deriving instance Lean.ToExpr for Resolved.WriteRules
deriving instance Lean.ToExpr for Resolved.Statement

end Belay.Sqlite.Model
