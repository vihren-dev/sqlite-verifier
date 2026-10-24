import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT 1 WHERE c(SELECT count(*) FROM t WHERE p)` over every database (ADR 0017, S4):
a condition on the number of rows of {lit}`t` for which {lit}`p` is true, such as a bound
{lit}`(SELECT count(*) FROM t) < 100`. When the catalog of the database has the table and {lit}`p` resolves in the
scope of the table, the claims {lit}`Holds` and {lit}`Empty` of the query are statements about the condition
{lit}`c` with the number of rows as the value of the subquery, when the expressions of {lit}`c` and {lit}`p` are calm
(no fallible call, no clock read and no counter read) and {lit}`c` resolves for every shape of a count query. Then
{lit}`Fails` does not hold. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT 1 WHERE c` with the subquery
{lit}`SELECT count(*) FROM t WHERE p`, where the catalog of the database has the table {lit}`t` at a position, {lit}`p`
resolves in the scope of the table, and {lit}`c` resolves, for every shape of a count query, to a condition
without a fallible call, the output of the script is the output of the step of the simple query without source
whose condition is the resolved {lit}`c`, with the count query of that table as its one subquery. Proof sketch:
{name}`Script.outputOn_query` with the resolution of {name}`resolveStatement_selectOne_count`. -/
theorem Script.outputOn_selectOne_count
    {script : Script} {db : Database} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {name : String} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression (.callStar name) none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition) { later := [countShape lowest] })
    (plain : mainCondition.any Resolved.Expr.isFallibleCall = false) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.selectOneWhere mainCondition)
        [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition text])) :=
  Script.outputOn_query script db _ parameters rest _ _ _ head
    (resolveStatement_selectOne_count runContext db.raw.connection.resolveState reference subFilter mainFilter position table
      subCondition mainCondition name text count arguments found subResolves mainResolves plain)


/-- For every script that is one read-only statement and is as in {name}`Script.outputOn_selectOne_count`, where {lit}`c` and {lit}`p` resolve to calm
expressions (no fallible call, no clock read and no counter read): {name}`Holds` of the script on the database
means that {lit}`c` is true in the context of the values in which the subquery is one row with the number of rows
of the table in scan order for which {lit}`p` is true ({name}`Resolved.countMatching`; all the rows without {lit}`WHERE`),
which is zero for an empty table. Proof sketch: {name}`Script.outputOn_selectOne_count` and
{name}`resolvedStepOutput_count_hasRows`. -/
theorem Holds.iff_selectOne_count
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {name : String} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression (.callStar name) none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition) { later := [countShape lowest] })
    (mainCalm : mainCondition.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    Holds script db isQuery ↔
      Resolved.truthy (mainCondition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.count (Resolved.countMatching (Resolved.EvalContext.bound parameters) subCondition
          { shape := table, rows := db.raw.rows.getD position [] })]) []) = true := by
  unfold Holds
  rw [Script.outputOn_selectOne_count head count arguments found subResolves mainResolves mainCalm.1, Option.any_some]
  exact resolvedStepOutput_count_hasRows 0 db.raw.connection parameters mainCondition position
    { shape := table, rows := db.raw.rows.getD position [] } subCondition text (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_count position _ subCondition text mainCalm subCalm)

/-- For every script as in {name}`Holds.iff_selectOne_count`: {name}`Empty` of the script on the database means that
{lit}`c` is not true in the same context. Proof sketch: {name}`Script.outputOn_selectOne_count` and
{name}`resolvedStepOutput_count_hasNoRows`. -/
theorem Empty.iff_selectOne_count
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {name : String} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression (.callStar name) none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition) { later := [countShape lowest] })
    (mainCalm : mainCondition.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    Empty script db isQuery ↔
      Resolved.truthy (mainCondition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.count (Resolved.countMatching (Resolved.EvalContext.bound parameters) subCondition
          { shape := table, rows := db.raw.rows.getD position [] })]) []) = false := by
  unfold Empty
  rw [Script.outputOn_selectOne_count head count arguments found subResolves mainResolves mainCalm.1, Option.any_some]
  exact resolvedStepOutput_count_hasNoRows 0 db.raw.connection parameters mainCondition position
    { shape := table, rows := db.raw.rows.getD position [] } subCondition text (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_count position _ subCondition text mainCalm subCalm)

/-- For every script as in {name}`Holds.iff_selectOne_count`, {name}`Fails` of the script on the database does not
hold: a calm query of a table that exists neither fails to resolve nor fails to run, and {lit}`count(*)` cannot
overflow. Proof sketch: {name}`Script.outputOn_selectOne_count` and {name}`resolvedStepOutput_count_not_isError`. -/
theorem Fails.not_selectOne_count
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {mainFilter : Syntax.Expr} {parameters : List Value}
    {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {subCondition : Option Resolved.Expr} {mainCondition : Resolved.Expr} {name : String} {text : String}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
      [Syntax.Subquery.mk [.expression (.callStar name) none text] (some reference) [] subFilter [] [] none none none none
        false none] none false none, parameters) :: rest)
    (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves runContext.profile.dqsDml [] [] (some mainFilter) (some mainCondition) { later := [countShape lowest] })
    (mainCalm : mainCondition.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectOne_count head count arguments found subResolves mainResolves mainCalm.1, Option.any_some,
    resolvedStepOutput_count_not_isError 0 db.raw.connection parameters mainCondition position
    { shape := table, rows := db.raw.rows.getD position [] } subCondition text (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_count position _ subCondition text mainCalm subCalm)]
  simp

end Belay.Sqlite
