import Belay.Sqlite.ExistsQuery
import Belay.Sqlite.NotExistsQuery

set_option doc.verso true

/-! The query forms {lit}`SELECT 1 WHERE [NOT] EXISTS (SELECT 1 FROM t WHERE p)` when {lit}`p` calls a
function that can fail (ADR 0017, S4): SQLite may evaluate a subquery for rows that the model does not reach,
so the model does not describe a failure inside a subquery, and none of {lit}`Holds`, {lit}`Empty` and
{lit}`Fails` holds of the query. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every query script whose first statement is {lit}`SELECT 1 WHERE EXISTS (SELECT 1 FROM t WHERE p)`, where
the catalog of the database has the table {lit}`t`, {lit}`p` resolves to a condition that reads no clock and no
counter, and some part of the condition is a call of a function that can fail ({name}`Resolved.Expr.isFallibleCall`),
none of {lit}`Holds`, {lit}`Empty` and {lit}`Fails` holds of the script on the database. The rows of the table do not matter. The source reference has no indexed query.
Proof sketch:
{name}`Script.outputOn_selectOne_exists` and {name}`resolvedStepOutput_selectOne_subquery_unmodeled`. -/
theorem Script.not_claims_selectOne_exists_of_fallible
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {subCondition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.exists 0)) [] [] none none
      [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (quiet : ∀ expression ∈ subCondition.toList, expression.Quiet)
    {expression : Resolved.Expr} (inCondition : expression ∈ subCondition.toList)
    (fallible : expression.any Resolved.Expr.isFallibleCall = true) :
    ¬ Holds script db isQuery ∧ ¬ Empty script db isQuery ∧ ¬ Fails script db isQuery := by
  have output := resolvedStepOutput_selectOne_subquery_unmodeled 0 position db.raw.connection parameters (.exists 0) subCondition
    ((Resolved.Expr.calm_exists 0).quiet) quiet inCondition fallible
  unfold Holds Empty Fails
  rw [Script.outputOn_selectOne_exists head namedSource arguments found resolves, Option.any_some, Option.any_some, Option.any_some,
    output.1, output.2.1, output.2.2]
  simp

/-- For every query script whose first statement is {lit}`SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t WHERE p)`, where
the catalog of the database has the table {lit}`t`, {lit}`p` resolves to a condition that reads no clock and no
counter, and some part of the condition is a call of a function that can fail ({name}`Resolved.Expr.isFallibleCall`),
none of {lit}`Holds`, {lit}`Empty` and {lit}`Fails` holds of the script on the database. The rows of the table do not matter. The source reference has no indexed query.
Proof sketch:
{name}`Script.outputOn_selectOne_notExists` and {name}`resolvedStepOutput_selectOne_subquery_unmodeled`. -/
theorem Script.not_claims_selectOne_notExists_of_fallible
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {subCondition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none none
      [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
      none false none, parameters) :: rest)
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (quiet : ∀ expression ∈ subCondition.toList, expression.Quiet)
    {expression : Resolved.Expr} (inCondition : expression ∈ subCondition.toList)
    (fallible : expression.any Resolved.Expr.isFallibleCall = true) :
    ¬ Holds script db isQuery ∧ ¬ Empty script db isQuery ∧ ¬ Fails script db isQuery := by
  have output := resolvedStepOutput_selectOne_subquery_unmodeled 0 position db.raw.connection parameters (.not (.exists 0)) subCondition
    (((Resolved.Expr.calm_not _).2 (Resolved.Expr.calm_exists 0)).quiet) quiet inCondition fallible
  unfold Holds Empty Fails
  rw [Script.outputOn_selectOne_notExists head namedSource arguments found resolves, Option.any_some, Option.any_some, Option.any_some,
    output.1, output.2.1, output.2.2]
  simp

end Belay.Sqlite
