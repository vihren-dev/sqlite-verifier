import Belay.Sqlite.Model.Resolution.QueryExprs
import Belay.Sqlite.Model.Resolution.ParameterOrder

set_option doc.verso true

/-! The CHECK constraints of CREATE TABLE and ADD COLUMN (ADR 0014, D2), resolved as
SQLite's {lit}`sqlite3EndTable` resolves them: after every other check of the definition,
in written order, as {lit}`WHERE` conditions over the table alone, with aggregates as
misuse and under the profile's {lit}`DQS_DDL`. Checked natively with 3.51.0. -/

namespace Belay.Sqlite.Model

/-- The model restriction of a resolved CHECK condition, or none: a time keyword or a date
and time function, which can give another value on each evaluation, a call of a connection counter
({name}`Resolved.Expr.isCounter`), whose value depends on the statements that ran before, and a JSON function
or another function whose evaluation can fail ({name}`Resolved.Expr.isFallibleCall`), are {name}`RestrictionKind.checkFunction`. -/
def checkIssue (resolved : Resolved.Expr) : Option ValueIssue :=
  if resolved.any Resolved.Expr.isNow || resolved.any Resolved.Expr.isDateCall ||
      resolved.any Resolved.Expr.isCounter ||
      resolved.any Resolved.Expr.isFallibleCall then some (.restriction [] .checkFunction)
  else none

/-- One CHECK constraint over the scope of its table: the condition and its label. A parameter
is {name}`ExprError.parameterInCheck`, in SQLite's order ({name}`prohibitParameter`). -/
def resolveCheck (dqs : Bool) (scope : Scope) (condition : Syntax.Expr) (label : String) :
    Except ValueIssue CheckConstraint := do
  prohibitParameter dqs scope .parameterInCheck condition
  let resolved ← Belay.Sqlite.Model.condition [] (resolveOperand dqs scope {} true condition)
  match checkIssue resolved with
  | some issue => .error issue
  | none => .ok { condition := resolved, label }

/-- The CHECK constraints of one column definition, in written order; the path of an issue
of constraint {lit}`item` is {lit}`[2, item, 0]` within the definition. -/
def columnChecks (dqs : Bool) (scope : Scope) (definition : Syntax.ColumnDefinition) :
    Except ValueIssue (List CheckConstraint) :=
  definition.constraints.zipIdx.filterMapM fun (constraint, item) => match constraint with
    | .check condition label => some <$> (resolveCheck dqs scope condition label).mapError (·.under [2, item, 0])
    | .notNull _ | .primaryKey .. | .unique _ | .default .. | .collate _ | .references .. | .generated .. | .deferral _ => .ok none

/-- The table with the CHECK constraints of its definitions and of its table constraints
resolved over the scope, in written order: each column's in {name}`CatalogColumn.checks`
(issue path {lit}`[1, column, 2, item, 0]`), then the table constraints' in
{name}`CatalogTable.checks` (issue path {lit}`[2, item, 0]`). -/
def resolveTableChecks (dqs : Bool) (scope : Scope) (table : CatalogTable)
    (definitions : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint) :
    Except ValueIssue CatalogTable := do
  let checked ← (table.columns.zip definitions).zipIdx.mapM fun ((column, definition), position) =>
    (fun checks => { column with checks }) <$> (columnChecks dqs scope definition).mapError (·.under [1, position])
  let tableChecks ← constraints.zipIdx.filterMapM fun (constraint, item) => match constraint with
    | .check condition label => some <$> (resolveCheck dqs scope condition label).mapError (·.under [2, item, 0])
    | .primaryKey .. | .unique .. | .foreignKey .. | .deferral _ => .ok none
  .ok { table with columns := checked ++ table.columns.drop definitions.length, checks := tableChecks }

end Belay.Sqlite.Model
