import Belay.Sqlite.SelectOneFrom

set_option doc.verso true

/-! The query form {lit}`SELECT 1 FROM t WHERE p` when {lit}`p` may fail (ADR 0017, S4): when a call of
{lit}`p` may fail on a row of the table, such as {lit}`abs(x) = 1` on a row {lit}`x = -9223372036854775808`,
the model does not describe the statement, and none of {lit}`Holds`, {lit}`Empty` and {lit}`Fails` holds of
it, whatever the other rows say. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every query script whose first statement is {lit}`SELECT 1 FROM t WHERE p`, where the catalog of the
database has the table {lit}`t` and {lit}`p` resolves to a condition that reads no clock and no counter, and
some part of the condition may fail ({name}`Resolved.Expr.mayFailOn`) on the empty row or on a row of the table
in the context of the values, none of {lit}`Holds`, {lit}`Empty` and {lit}`Fails` holds of the script on the
database. The condition may be true for a row or for no
row. Proof sketch: {name}`Script.outputOn_selectOne` and {name}`resolvedStepOutput_simpleTable_unmodeled`. -/
theorem Script.not_claims_selectOne_of_mayFail
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none []
      none false none, parameters) :: rest)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) [] filter
      condition)
    (quiet : ∀ expression ∈ condition.toList, expression.Quiet)
    {row : List Value} (member : row ∈ [] :: Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] })
    {expression : Resolved.Expr} (inCondition : expression ∈ condition.toList)
    (fails : expression.mayFailOn (Resolved.EvalContext.bound parameters) row = true) :
    ¬ Holds script db isQuery ∧ ¬ Empty script db isQuery ∧ ¬ Fails script db isQuery := by
  have output := resolvedStepOutput_simpleTable_unmodeled 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition _ _
    (Database.table_of_findTable db.raw _ position table found) (Resolved.Statement.Quiet.selectOne position condition quiet)
    member inCondition fails
  unfold Holds Empty Fails
  rw [Script.outputOn_selectOne head arguments found resolves, Option.any_some, Option.any_some, Option.any_some,
    output.1, output.2.1, output.2.2]
  simp

end Belay.Sqlite
