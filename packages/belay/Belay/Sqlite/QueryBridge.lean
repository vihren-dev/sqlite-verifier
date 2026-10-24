import Belay.Sqlite.QueryLaws
import Belay.Sqlite.Model

set_option doc.verso true

/-! From {lit}`Holds`, {lit}`Empty` and {lit}`Fails` to the model's query (ADR 0017, S4): the
output of a script that starts with a statement is the output of the step of that statement
({name}`Belay.Sqlite.Model.runScriptStep_output`), and when resolution turns the statement into a
query, the claims are statements about the source rows of that query, its run and its one result.
The query forms in the modules after this one give the resolved query and these three facts. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every script that starts with a statement and every database, the output of the script
({name}`Script.outputOn`) is the output of the step of the statement on the connection to the
database ({name}`runScriptStep_output`): the reason of the restriction when resolution refuses it,
and otherwise {name}`resolvedStepOutput` of the resolved statement. Proof sketch: the first output of
a run is the output of its first step ({name}`runScriptFrom_head_cons`). -/
theorem Script.outputOn_eq_step (script : Script) (db : Database) (statement : Syntax.Statement)
    (parameters : List Value) (rest : List (Syntax.Statement × List Value))
    (head : script.statements = (statement, parameters) :: rest) :
    script.outputOn db =
      some (match resolveStatement runContext db.raw.connection.resolveState statement with
        | .error restriction => .unmodeled restriction.reason
        | .ok (resolved, _) => resolvedStepOutput none 0 db.raw.connection parameters resolved) := by
  unfold Script.outputOn Database.Raw.run Script.runOn
  rw [head, runScriptFrom_head_cons, runScriptStep_output]
  rfl

/-- For every script that starts with a statement that resolution turns into the query
{lit}`query` with the subqueries {lit}`subqueries`, the output of the script is the output of the step
of that query. Proof sketch: {name}`Script.outputOn_eq_step` with the resolved statement. -/
theorem Script.outputOn_query (script : Script) (db : Database) (statement : Syntax.Statement)
    (parameters : List Value) (rest : List (Syntax.Statement × List Value))
    (query : Resolved.Query) (subqueries : List Resolved.Query) (after : ResolveState)
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query query subqueries, after)) :
    script.outputOn db =
      some (resolvedStepOutput none 0 db.raw.connection parameters (.query query subqueries)) := by
  rw [Script.outputOn_eq_step script db statement parameters rest head, resolved]

/-- For every query script that starts with a statement that resolution turns into the query
{lit}`query` (without a clock read and without a counter read that is unknown), whose source rows
{lit}`source` and bound window {lit}`bound` exist: {lit}`Holds` of the script on the database means
that the model describes the query (its subqueries are plain and the source rows have no fault
{lit}`may`), the run of the query has no window mismatch, no overflow and no fault, and the one
result of the bound query has a row. Proof sketch: {name}`Script.outputOn_query` and
{name}`resolvedStepOutput_query_hasRows`. -/
theorem Holds.iff_query {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {query bound : Resolved.Query} {subqueries : List Resolved.Query} {after : ResolveState}
    {source : Resolved.SourceRows}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query query subqueries, after))
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : db.raw.connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (db.raw.connection.queryContext parameters query subqueries) db.raw = some source)
    (window : query.bindWindow parameters = some bound) :
    Holds script db isQuery ↔
      Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true ∧ source.fault ≠ .may ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).mismatch = false ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).overflow = false ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).fault = .none ∧
        bound.results (db.raw.connection.queryContext parameters query subqueries) source.rows ≠ [] := by
  unfold Holds
  rw [Script.outputOn_query script db statement parameters rest query subqueries after head resolved, Option.any_some]
  exact resolvedStepOutput_query_hasRows 0 db.raw.connection parameters query bound subqueries source noClock known found window

/-- For every query script that starts with a statement that resolution turns into the query
{lit}`query` (as for {name}`Holds.iff_query`): {lit}`Empty` of the script on the database means that
the model describes the query, the run has no window mismatch, no overflow and no fault, and the
one result of the bound query has no row. Proof sketch: {name}`Script.outputOn_query` and
{name}`resolvedStepOutput_query_hasNoRows`. -/
theorem Empty.iff_query {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {query bound : Resolved.Query} {subqueries : List Resolved.Query} {after : ResolveState}
    {source : Resolved.SourceRows}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query query subqueries, after))
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : db.raw.connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (db.raw.connection.queryContext parameters query subqueries) db.raw = some source)
    (window : query.bindWindow parameters = some bound) :
    Empty script db isQuery ↔
      Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true ∧ source.fault ≠ .may ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).mismatch = false ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).overflow = false ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).fault = .none ∧
        bound.results (db.raw.connection.queryContext parameters query subqueries) source.rows = [] := by
  unfold Empty
  rw [Script.outputOn_query script db statement parameters rest query subqueries after head resolved, Option.any_some]
  exact resolvedStepOutput_query_hasNoRows 0 db.raw.connection parameters query bound subqueries source noClock known found window

/-- For every query script that starts with a statement that resolution turns into the query
{lit}`query` (as for {name}`Holds.iff_query`, without a bound window): {lit}`Fails` of the script on
the database means that the model describes the query and the run has a window mismatch, an
overflow or a failing function. Proof sketch: {name}`Script.outputOn_query` and
{name}`resolvedStepOutput_query_isError`. -/
theorem Fails.iff_query {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {query : Resolved.Query} {subqueries : List Resolved.Query} {after : ResolveState}
    {source : Resolved.SourceRows}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement =
      .ok (.query query subqueries, after))
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : db.raw.connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (db.raw.connection.queryContext parameters query subqueries) db.raw = some source) :
    Fails script db isQuery ↔
      Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true ∧ source.fault ≠ .may ∧
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).fault ≠ .may ∧
        ((query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).mismatch = true ∨
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).overflow = true ∨
        (query.run (db.raw.connection.queryContext parameters query subqueries) source.rows).fault = .must) := by
  unfold Fails
  rw [Script.outputOn_query script db statement parameters rest query subqueries after head resolved, Option.any_some]
  exact resolvedStepOutput_query_isError 0 db.raw.connection parameters query subqueries source noClock known found

end Belay.Sqlite
