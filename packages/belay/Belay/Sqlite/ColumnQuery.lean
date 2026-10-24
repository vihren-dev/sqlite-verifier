import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT 1 WHERE c(SELECT e FROM t WHERE p)` over every database (ADR 0017, S4): a condition
{lit}`c` on a subquery with one column, such as {lit}`$x IN (SELECT id FROM t WHERE p)`. When the catalog of the database
has the table, {lit}`e` is no function call and resolves in the scope of the table, {lit}`p` resolves in the scope of
the table, and {lit}`c` resolves for every shape of a one-column subquery, the claims {lit}`Holds` and {lit}`Empty` of
the query are statements about the condition {lit}`c` with the values of {lit}`e` for the kept rows as the rows of the
subquery, when the expressions of {lit}`c`, {lit}`p` and {lit}`e` are calm and {lit}`c` reads no scalar subquery. Then
{lit}`Fails` does not hold. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT 1 WHERE c` with the subquery {lit}`SELECT e FROM t WHERE p`,
where the catalog of the database has the table {lit}`t` at a position, {lit}`e` is no function call, has no aggregate call
and resolves in the scope of the table to an expression without a fallible call, {lit}`p` resolves in the scope of the table,
and {lit}`c` resolves, for every lowest position of a subquery with one column ({name}`scalarShape`), to a condition without a
fallible call, the output of the script is the output of the step of the simple query without source whose condition is the
resolved {lit}`c`, with the simple query of that table with the resolved {lit}`p` and {lit}`e` as its one subquery. Proof sketch:
{name}`Script.outputOn_query` with the resolution of {name}`resolveStatement_selectOne_scalar`. -/
theorem Script.outputOn_selectOne_column
    {script : Script} {db : Database} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {value : Syntax.Expr}
    {expression : Resolved.Expr} {affinity : Option Affinity} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operand : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0 } false value = .ok (expression, affinity))
    (valuePlain : expression.any Resolved.Expr.isFallibleCall = false)
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition)
        { later := [scalarShape affinity value.explicitCollation (value.columnCollation
          (tableScope db.raw.catalog reference position table)) lowest] })
    (plain : mainCondition.any Resolved.Expr.isFallibleCall = false) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.selectOneWhere mainCondition)
        [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar expression]
          [(definedName (tableScope db.raw.catalog reference position table) value).getD text]])) :=
  Script.outputOn_query script db _ parameters rest _ _ _ head
    (resolveStatement_selectOne_scalar runContext db.raw.connection.resolveState reference value text subFilter mainFilter
      position table subCondition mainCondition expression affinity notCall noAggregate arguments found operand valuePlain
      subResolves mainResolves plain)

/-- For every script that is one read-only statement and is as in {name}`Script.outputOn_selectOne_column`, where {lit}`c`, {lit}`p`
and {lit}`e` resolve to calm expressions (no fallible call, no clock read and no counter read) and {lit}`c` reads no scalar
subquery: {name}`Holds` of the script on the database means that {lit}`c` is true in the context of the values in which the
subquery has one row for each row of the table in scan order for which {lit}`p` is true, with the value of {lit}`e` for the
row ({name}`Resolved.scalarRows`), and no fault. The formula requires nothing of the rows when {lit}`c` ignores the subquery.
Proof sketch: {name}`Script.outputOn_selectOne_column` and {name}`resolvedStepOutput_scalar_hasRows`. -/
theorem Holds.iff_selectOne_column
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {value : Syntax.Expr}
    {expression : Resolved.Expr} {affinity : Option Affinity} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operand : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0 } false value = .ok (expression, affinity))
    (valuePlain : expression.any Resolved.Expr.isFallibleCall = false)
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition)
        { later := [scalarShape affinity value.explicitCollation (value.columnCollation
          (tableScope db.raw.catalog reference position table)) lowest] })
    (noScalar : mainCondition.any (· matches .subquery _) = false)
    (mainCalm : mainCondition.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm)
    (valueCalm : expression.Calm) :
    Holds script db isQuery ↔
      Resolved.truthy (mainCondition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.certain (Resolved.scalarRows (Resolved.EvalContext.bound parameters) subCondition expression
          { shape := table, rows := db.raw.rows.getD position [] })]) []) = true := by
  unfold Holds
  rw [Script.outputOn_selectOne_column head notCall noAggregate arguments found operand valuePlain subResolves mainResolves mainCalm.1, Option.any_some]
  exact resolvedStepOutput_scalar_hasRows 0 db.raw.connection parameters mainCondition position
    { shape := table, rows := db.raw.rows.getD position [] } subCondition expression _ (Database.table_of_findTable db.raw _ position table found) noScalar
    (Resolved.Statement.Calm.selectOne_scalar position _ subCondition expression _ mainCalm subCalm valueCalm)

/-- For every script as in {name}`Holds.iff_selectOne_column`: {name}`Empty` of the script on the database means that {lit}`c` is
not true in the same context. Proof sketch: {name}`Script.outputOn_selectOne_column` and
{name}`resolvedStepOutput_scalar_hasNoRows`. -/
theorem Empty.iff_selectOne_column
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {value : Syntax.Expr}
    {expression : Resolved.Expr} {affinity : Option Affinity} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operand : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0 } false value = .ok (expression, affinity))
    (valuePlain : expression.any Resolved.Expr.isFallibleCall = false)
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition)
        { later := [scalarShape affinity value.explicitCollation (value.columnCollation
          (tableScope db.raw.catalog reference position table)) lowest] })
    (noScalar : mainCondition.any (· matches .subquery _) = false)
    (mainCalm : mainCondition.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm)
    (valueCalm : expression.Calm) :
    Empty script db isQuery ↔
      Resolved.truthy (mainCondition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.certain (Resolved.scalarRows (Resolved.EvalContext.bound parameters) subCondition expression
          { shape := table, rows := db.raw.rows.getD position [] })]) []) = false := by
  unfold Empty
  rw [Script.outputOn_selectOne_column head notCall noAggregate arguments found operand valuePlain subResolves mainResolves mainCalm.1, Option.any_some]
  exact resolvedStepOutput_scalar_hasNoRows 0 db.raw.connection parameters mainCondition position
    { shape := table, rows := db.raw.rows.getD position [] } subCondition expression _ (Database.table_of_findTable db.raw _ position table found) noScalar
    (Resolved.Statement.Calm.selectOne_scalar position _ subCondition expression _ mainCalm subCalm valueCalm)

/-- For every script as in {name}`Holds.iff_selectOne_column`, {name}`Fails` of the script on the database does not hold: a calm
query of a table that exists neither fails to resolve nor fails to run. Proof sketch:
{name}`Script.outputOn_selectOne_column` and {name}`resolvedStepOutput_scalar_not_isError`. -/
theorem Fails.not_selectOne_column
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {value : Syntax.Expr}
    {expression : Resolved.Expr} {affinity : Option Affinity} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operand : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := some 0 } false value = .ok (expression, affinity))
    (valuePlain : expression.any Resolved.Expr.isFallibleCall = false)
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition)
        { later := [scalarShape affinity value.explicitCollation (value.columnCollation
          (tableScope db.raw.catalog reference position table)) lowest] })
    (noScalar : mainCondition.any (· matches .subquery _) = false)
    (mainCalm : mainCondition.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm)
    (valueCalm : expression.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectOne_column head notCall noAggregate arguments found operand valuePlain subResolves mainResolves mainCalm.1, Option.any_some,
    resolvedStepOutput_scalar_not_isError 0 db.raw.connection parameters mainCondition position
    { shape := table, rows := db.raw.rows.getD position [] } subCondition expression _ (Database.table_of_findTable db.raw _ position table found) noScalar
    (Resolved.Statement.Calm.selectOne_scalar position _ subCondition expression _ mainCalm subCalm valueCalm)]
  simp

end Belay.Sqlite
