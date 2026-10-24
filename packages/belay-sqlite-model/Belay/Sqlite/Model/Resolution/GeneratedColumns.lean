import Belay.Sqlite.Model.Resolution.TableChecks
import Belay.Sqlite.Model.Resolution.NondeterministicCalls

set_option doc.verso true

/-! The generated columns of CREATE TABLE (ADR 0014, D5), resolved as SQLite's
{lit}`sqlite3EndTable` resolves them: after the CHECK constraints, each expression over the
table's columns alone, with aggregates as misuse, without the rowid, and under the profile's
{lit}`DQS_DDL`. Checked natively with 3.51.0. -/

namespace Belay.Sqlite.Model

/-- The issue of a resolved generated expression, or none: a {lit}`CURRENT_TIME`,
{lit}`CURRENT_DATE` or {lit}`CURRENT_TIMESTAMP` is SQLite's
{name}`ExprError.nondeterministicGenerated`; a date and time function, whose {lit}`'now'`
SQLite refuses only when it writes a row, and a JSON function or another function whose
evaluation can fail ({name}`Resolved.Expr.isFallibleCall`), are
{name}`RestrictionKind.generatedFunction`. -/
def generatedIssue (resolved : Resolved.Expr) : Option ValueIssue :=
  if resolved.any Resolved.Expr.isNow then some (.prepare .nondeterministicGenerated)
  else if resolved.any Resolved.Expr.isDateCall || resolved.any Resolved.Expr.isFallibleCall then
    some (.restriction [] .generatedFunction)
  else none

/-- The expression of the generated constraint of a definition, or none. -/
def Syntax.ColumnDefinition.generatedExpression (definition : Syntax.ColumnDefinition) : Option (Nat × Syntax.Expr) :=
  definition.constraints.zipIdx.findSome? fun (constraint, item) => match constraint with
    | .generated expression _ => some (item, expression)
    | .notNull _ | .primaryKey .. | .unique _ | .default .. | .collate _ | .check .. | .references .. | .deferral _ => none

/-- One generated expression over the scope: a parameter is
{name}`ExprError.parameterInGenerated` in SQLite's order ({name}`prohibitParameter`); a qualified name is
{name}`ExprError.qualifiedGenerated`; a call of a function that is not deterministic is
{name}`ExprError.nondeterministicGenerated` where SQLite's walk finds no other error
({name}`prohibitNondeterministic`); else the resolved operand and its {name}`generatedIssue`. -/
def resolveGeneratedExpression (dqs : Bool) (scope : Scope) (expression : Syntax.Expr) :
    Except ValueIssue Resolved.Expr := do
  prohibitParameter dqs scope .parameterInGenerated expression
  if expression.hasQualifiedName then throw (.prepare .qualifiedGenerated)
  prohibitNondeterministic dqs scope .nondeterministicGenerated expression
  let (resolved, _) ← resolveOperand dqs scope {} true expression
  match generatedIssue resolved with
  | some issue => .error issue
  | none => .ok resolved

/-- The positions of the generated columns that settle when each generated column waits for
the generated columns that it reads: after one pass per generated column, a column that is
not settled is on a loop. The passes use structural recursion, so the kernel reduces them. -/
def settledGenerated (columns : List CatalogColumn) : List Nat :=
  let generated := columns.zipIdx.filterMap fun (column, position) =>
    column.generated.map fun how => (position, how.expression.reads columns.length)
  let isGenerated := fun position => generated.any (·.1 == position)
  generated.foldl (fun settled _ => generated.filterMap fun (position, reads) =>
    if reads.all fun read => !isGenerated read || settled.contains read then some position else none) []

/-- Whether the generated columns of the table have no loop ({name}`settledGenerated`). -/
def CatalogTable.generatedLoopFree (table : CatalogTable) : Bool :=
  (settledGenerated table.columns).length == (table.columns.filter (·.generated.isSome)).length

/-- The table with the expression of each generated column resolved over the scope, in
column order (issue path {lit}`[1, column, 2, item, 0]`); a loop is
{name}`RestrictionKind.generatedLoop`, which SQLite reports while CREATE TABLE runs. -/
def resolveGeneratedColumns (dqs : Bool) (scope : Scope) (table : CatalogTable)
    (definitions : List Syntax.ColumnDefinition) : Except ValueIssue CatalogTable := do
  let columns ← (table.columns.zip definitions).zipIdx.mapM fun ((column, definition), position) =>
    match column.generated, definition.generatedExpression with
    | some how, some (item, expression) =>
      (fun resolved => { column with generated := some { how with expression := resolved } }) <$>
        (resolveGeneratedExpression dqs scope expression).mapError (·.under [1, position, 2, item, 0])
    | some _, none | none, some _ | none, none => .ok column
  let resolved := { table with columns := columns ++ table.columns.drop definitions.length }
  if resolved.generatedLoopFree then .ok resolved else .error (.restriction [1] .generatedLoop)

end Belay.Sqlite.Model
