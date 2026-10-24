import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT 1 WHERE EXISTS (SELECT 1 FROM t WHERE p)` over every database (ADR 0017, S4):
"some row of {lit}`t` satisfies {lit}`p`". When the catalog of the database has the table and {lit}`p` resolves in the
scope of the table, the claims {lit}`Holds` and {lit}`Empty` of the query are statements about the rows of the
table and the resolved condition, and {lit}`Fails` does not hold. The form {lit}`NOT EXISTS` is in
{lit}`NotExistsQuery.lean`. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT 1 WHERE EXISTS (SELECT 1 FROM t WHERE p)`, where the
catalog of the database has the table {lit}`t` at a position and {lit}`p` resolves in the scope of the table, the
output of the script is the output of the step of the simple query without source whose condition is
{lit}`EXISTS` of subquery 0, with the simple query of that table as its one subquery. Proof sketch:
{name}`Script.outputOn_query` with the resolution of {name}`resolveStatement_selectOne_exists`. -/
theorem Script.outputOn_selectOne_exists
    {script : Script} {db : Database} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {subCondition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.exists 0)) [] [] none none
      [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
      none false none, parameters) :: rest)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 }) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.selectOneWhere (.exists 0))
        [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar (.literal (.integer 1))] ["1"]])) :=
  Script.outputOn_query script db _ parameters rest _ _ _ head
    (resolveStatement_selectOne_exists runContext db.raw.connection.resolveState reference subFilter position table
      subCondition arguments found resolves)

/-- For every script as in {name}`Script.outputOn_selectOne_exists` where the condition {lit}`p` resolves to a calm
condition (it has no fallible call, no clock and no counter read): {lit}`Holds` of the script on the database
means that there is a row of the table in scan order (rowid order, or primary-key order for a {lit}`WITHOUT ROWID` table) for which the condition is true, evaluated in the context of the values (without {lit}`WHERE` in
the subquery: the table has a row). Proof sketch: {name}`Script.outputOn_selectOne_exists` and
{name}`resolvedStepOutput_exists_hasRows`. -/
theorem Holds.iff_selectOne_exists
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {subCondition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.exists 0)) [] [] none none
      [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
      none false none, parameters) :: rest)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (calm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    Holds script db isQuery ↔
      ∃ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        subCondition.all (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  unfold Holds
  rw [Script.outputOn_selectOne_exists head arguments found resolves, Option.any_some]
  exact resolvedStepOutput_exists_hasRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } subCondition _ _ (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_subquery position _ subCondition (Resolved.Expr.calm_exists _) calm)

/-- For every script as in {name}`Script.outputOn_selectOne_exists` where the condition {lit}`p` resolves to a calm
condition (it has no fallible call, no clock and no counter read): {lit}`Empty` of the script on the database
means that the condition is not true for any row of the table (without {lit}`WHERE` in the subquery: the table
has no row). Proof sketch: {name}`Script.outputOn_selectOne_exists` and
{name}`resolvedStepOutput_exists_hasNoRows`. -/
theorem Empty.iff_selectOne_exists
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {subCondition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.exists 0)) [] [] none none
      [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
      none false none, parameters) :: rest)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (calm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    Empty script db isQuery ↔
      ∀ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        subCondition.all (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  unfold Empty
  rw [Script.outputOn_selectOne_exists head arguments found resolves, Option.any_some]
  exact resolvedStepOutput_exists_hasNoRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } subCondition _ _ (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_subquery position _ subCondition (Resolved.Expr.calm_exists _) calm)

/-- For every script as in {name}`Holds.iff_selectOne_exists`, {lit}`Fails` of the script on the database does not
hold: a calm query of a table that exists neither fails to resolve nor fails to run. Proof sketch:
{name}`Script.outputOn_selectOne_exists` and {name}`resolvedStepOutput_exists_not_isError`. -/
theorem Fails.not_selectOne_exists
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {subFilter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {subCondition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression (.numeric "1") none "1"] none [] (some (.exists 0)) [] [] none none
      [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
      none false none, parameters) :: rest)
    (arguments : reference.arguments = none) (found : db.raw.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (calm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectOne_exists head arguments found resolves, Option.any_some,
    resolvedStepOutput_exists_not_isError 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } subCondition _ _ (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.selectOne_subquery position _ subCondition (Resolved.Expr.calm_exists _) calm)]
  simp

end Belay.Sqlite
