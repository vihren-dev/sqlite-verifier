import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT agg(x) FROM t WHERE p` over every database (ADR 0017, S4), where {lit}`agg` is an
aggregate of one operand, such as {lit}`SELECT sum(c) FROM t`: the whole table is one group, so the query has one row,
also for a table without a row, unless the aggregate fails. The only aggregate that fails is {lit}`sum`, with
{lit}`integer overflow`. When the catalog of the database has the table, and the operand and {lit}`p` resolve in the
scope of the table to expressions that are calm (no fallible call, no clock read and no counter read), the claims
{lit}`Holds` and {lit}`Fails` of the query are statements about the aggregate over the rows of the table that
{lit}`p` keeps, and {lit}`Empty` does not hold. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT agg(x) FROM t WHERE p` (or without {lit}`WHERE`), where the
catalog of the database has the table {lit}`t` at a position, the name {lit}`agg` names an aggregate of one operand that
does not write JSON ({name}`aggregateNamed`), and the operand and {lit}`p` resolve in the scope of the table, the output
of the script is the output of the step of the whole-table aggregate query of that table
({name}`Resolved.Query.aggregateOf`). The source reference has no indexed query.
Proof sketch: {name}`Script.outputOn_query` with the resolution of
{name}`resolveStatement_select_aggregate`. -/
theorem Script.outputOn_selectAggregate
    {script : Script} {db : Database} {reference : Syntax.TableReference} {filter : Option Syntax.Expr}
    {parameters : List Value} {rest : List (Syntax.Statement × List Value)} {position : Nat} {table : CatalogTable}
    {condition : Option Resolved.Expr} {name : String} {operand : Syntax.Expr} {alias : Option Identifier}
    {text : String} {build : Resolved.Expr → Resolved.Aggregate} {resolved : Resolved.Expr}
    {affinity : Option Affinity} {aggregate : Resolved.Aggregate}
    (head : script.statements = (.select [.expression (.call name [operand]) alias text] (some reference) [] filter [] []
      none none [] none false none, parameters) :: rest)
    (named : aggregateNamed name = some build) (namedSource : reference.query = none) (arguments : reference.arguments = none)
    (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operandOk : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := none, later := [] } true operand = .ok (resolved, affinity))
    (noJson : (build resolved).writesJson = false)
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      ((resultAliases (tableScope db.raw.catalog reference position table)
        [.expression (.call name [operand]) alias text]).filterMap id) filter condition { current := none, later := [] })
    (aggregateIs : aggregate =
      (build resolved).withCollation (operand.collationIn (tableScope db.raw.catalog reference position table))) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate
        ((alias.map (·.text)).getD text)) [])) := by
  subst aggregateIs
  exact Script.outputOn_query script db _ parameters rest _ [] _ head
    (resolveStatement_select_aggregate runContext db.raw.connection.resolveState reference filter name operand alias text
      build named position table resolved affinity condition namedSource arguments found operandOk noJson resolves)

/-- For every script as in {name}`Script.outputOn_selectAggregate` that is one read-only statement, where {lit}`p` and
the operand resolve to calm expressions (no fallible call, no clock read and no counter read): {name}`Holds` of the
script on the database means that the aggregate does not fail ({name}`Resolved.Aggregate.fails`) over the rows of the
table in scan order for which the condition is true, in the context of the values; without {lit}`WHERE`, over all the
rows. The query has a row also for a table without a row. The source reference has no indexed query.
Proof sketch: {name}`Script.outputOn_selectAggregate` and
{name}`resolvedStepOutput_aggregateTable_hasRows`. -/
theorem Holds.iff_selectAggregate
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr} {name : String}
    {operand : Syntax.Expr} {alias : Option Identifier} {text : String} {build : Resolved.Expr → Resolved.Aggregate}
    {resolved : Resolved.Expr} {affinity : Option Affinity} {aggregate : Resolved.Aggregate}
    (head : script.statements = (.select [.expression (.call name [operand]) alias text] (some reference) [] filter [] []
      none none [] none false none, parameters) :: rest)
    (named : aggregateNamed name = some build) (namedSource : reference.query = none) (arguments : reference.arguments = none)
    (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operandOk : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := none, later := [] } true operand = .ok (resolved, affinity))
    (noJson : (build resolved).writesJson = false)
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      ((resultAliases (tableScope db.raw.catalog reference position table)
        [.expression (.call name [operand]) alias text]).filterMap id) filter condition { current := none, later := [] })
    (aggregateIs : aggregate =
      (build resolved).withCollation (operand.collationIn (tableScope db.raw.catalog reference position table)))
    (conditionCalm : ∀ expression ∈ condition.toList, expression.Calm)
    (operandsCalm : ∀ expression ∈ (Resolved.Output.aggregate aggregate).operands, expression.Calm) :
    Holds script db isQuery ↔
      aggregate.fails (Resolved.EvalContext.bound parameters)
        ((Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }).filter fun row =>
          condition.all fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) =
        false := by
  unfold Holds
  rw [Script.outputOn_selectAggregate head named namedSource arguments found operandOk noJson resolves aggregateIs, Option.any_some]
  exact resolvedStepOutput_aggregateTable_hasRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition aggregate _
    (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.aggregateOf_first position _ aggregate _ conditionCalm operandsCalm)

/-- For every script as in {name}`Holds.iff_selectAggregate`, {name}`Empty` of the script on the database does not hold:
the query has one row unless the aggregate fails, and then it has an error. The source reference has no indexed query.
Proof sketch:
{name}`Script.outputOn_selectAggregate` and {name}`resolvedStepOutput_aggregateTable_not_hasNoRows`. -/
theorem Empty.not_selectAggregate
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr} {name : String}
    {operand : Syntax.Expr} {alias : Option Identifier} {text : String} {build : Resolved.Expr → Resolved.Aggregate}
    {resolved : Resolved.Expr} {affinity : Option Affinity} {aggregate : Resolved.Aggregate}
    (head : script.statements = (.select [.expression (.call name [operand]) alias text] (some reference) [] filter [] []
      none none [] none false none, parameters) :: rest)
    (named : aggregateNamed name = some build) (namedSource : reference.query = none) (arguments : reference.arguments = none)
    (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operandOk : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := none, later := [] } true operand = .ok (resolved, affinity))
    (noJson : (build resolved).writesJson = false)
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      ((resultAliases (tableScope db.raw.catalog reference position table)
        [.expression (.call name [operand]) alias text]).filterMap id) filter condition { current := none, later := [] })
    (aggregateIs : aggregate =
      (build resolved).withCollation (operand.collationIn (tableScope db.raw.catalog reference position table)))
    (conditionCalm : ∀ expression ∈ condition.toList, expression.Calm)
    (operandsCalm : ∀ expression ∈ (Resolved.Output.aggregate aggregate).operands, expression.Calm) :
    ¬ Empty script db isQuery := by
  unfold Empty
  rw [Script.outputOn_selectAggregate head named namedSource arguments found operandOk noJson resolves aggregateIs, Option.any_some]
  rw [resolvedStepOutput_aggregateTable_not_hasNoRows 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition aggregate _
    (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.aggregateOf_first position _ aggregate _ conditionCalm operandsCalm)]
  simp

/-- For every script as in {name}`Holds.iff_selectAggregate`: {name}`Fails` of the script on the database means that the
aggregate fails ({name}`Resolved.Aggregate.fails`) over the rows of the table in scan order for which the condition is
true. Only {lit}`sum` can fail, with {lit}`integer overflow`. The source reference has no indexed query.
Proof sketch: {name}`Script.outputOn_selectAggregate` and
{name}`resolvedStepOutput_aggregateTable_isError`. -/
theorem Fails.iff_selectAggregate
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {reference : Syntax.TableReference}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {position : Nat} {table : CatalogTable} {condition : Option Resolved.Expr} {name : String}
    {operand : Syntax.Expr} {alias : Option Identifier} {text : String} {build : Resolved.Expr → Resolved.Aggregate}
    {resolved : Resolved.Expr} {affinity : Option Affinity} {aggregate : Resolved.Aggregate}
    (head : script.statements = (.select [.expression (.call name [operand]) alias text] (some reference) [] filter [] []
      none none [] none false none, parameters) :: rest)
    (named : aggregateNamed name = some build) (namedSource : reference.query = none) (arguments : reference.arguments = none)
    (found : db.raw.catalog.findTable reference.table = some (position, table))
    (operandOk : resolveOperand runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      { current := none, later := [] } true operand = .ok (resolved, affinity))
    (noJson : (build resolved).writesJson = false)
    (resolves : FilterResolves runContext.profile.dqsDml (tableScope db.raw.catalog reference position table)
      ((resultAliases (tableScope db.raw.catalog reference position table)
        [.expression (.call name [operand]) alias text]).filterMap id) filter condition { current := none, later := [] })
    (aggregateIs : aggregate =
      (build resolved).withCollation (operand.collationIn (tableScope db.raw.catalog reference position table)))
    (conditionCalm : ∀ expression ∈ condition.toList, expression.Calm)
    (operandsCalm : ∀ expression ∈ (Resolved.Output.aggregate aggregate).operands, expression.Calm) :
    Fails script db isQuery ↔
      aggregate.fails (Resolved.EvalContext.bound parameters)
        ((Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }).filter fun row =>
          condition.all fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) =
        true := by
  unfold Fails
  rw [Script.outputOn_selectAggregate head named namedSource arguments found operandOk noJson resolves aggregateIs, Option.any_some]
  exact resolvedStepOutput_aggregateTable_isError 0 position db.raw.connection parameters
    { shape := table, rows := db.raw.rows.getD position [] } condition aggregate _
    (Database.table_of_findTable db.raw _ position table found)
    (Resolved.Statement.Calm.aggregateOf_first position _ aggregate _ conditionCalm operandsCalm)

end Belay.Sqlite
