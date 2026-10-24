import Belay.Sqlite.QueryBridge

set_option doc.verso true

/-! Shared resolution and failure cases for every query form. Successful form laws use the
catalog and rows; these laws retain prepare errors and unmodeled outputs without repeating
the interpreter in each form's proof. -/

namespace Belay.Sqlite
open Belay.Sqlite.Model

/-- For every query script beginning with a statement, {name}`Holds` means that resolution
succeeds and its resolved step has rows. A resolver restriction makes the proposition false.
The resolved step includes clock, counter and support checks and execution errors.
Proof sketch: apply {name}`Script.outputOn_eq_step` to the definition of {name}`Holds`. -/
theorem Holds.iff_step {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    (head : script.statements = (statement, parameters) :: rest) :
    Holds script db isQuery ↔
      match resolveStatement runContext db.raw.connection.resolveState statement with
      | .error _ => False
      | .ok (resolved, _) => (resolvedStepOutput none 0 db.raw.connection parameters resolved).hasRows = true := by
  unfold Holds
  rw [Script.outputOn_eq_step script db statement parameters rest head]
  cases resolveStatement runContext db.raw.connection.resolveState statement <;>
    simp [Output.hasRows]

/-- For every query script beginning with a statement, {name}`Empty` means that resolution
succeeds and its resolved step has no rows. A resolver restriction makes the proposition false.
Proof sketch: apply {name}`Script.outputOn_eq_step` to the definition of {name}`Empty`. -/
theorem Empty.iff_step {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    (head : script.statements = (statement, parameters) :: rest) :
    Empty script db isQuery ↔
      match resolveStatement runContext db.raw.connection.resolveState statement with
      | .error _ => False
      | .ok (resolved, _) => (resolvedStepOutput none 0 db.raw.connection parameters resolved).hasNoRows = true := by
  unfold Empty
  rw [Script.outputOn_eq_step script db statement parameters rest head]
  cases resolveStatement runContext db.raw.connection.resolveState statement <;>
    simp [Output.hasNoRows]

/-- For every query script beginning with a statement, {name}`Fails` means that resolution
succeeds and its resolved step gives an error. This includes a resolved prepare error, such as
a missing table or column. A resolver restriction makes the proposition false.
Proof sketch: apply {name}`Script.outputOn_eq_step` to the definition of {name}`Fails`. -/
theorem Fails.iff_step {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    (head : script.statements = (statement, parameters) :: rest) :
    Fails script db isQuery ↔
      match resolveStatement runContext db.raw.connection.resolveState statement with
      | .error _ => False
      | .ok (resolved, _) => (resolvedStepOutput none 0 db.raw.connection parameters resolved).isError = true := by
  unfold Fails
  rw [Script.outputOn_eq_step script db statement parameters rest head]
  cases resolveStatement runContext db.raw.connection.resolveState statement <;>
    simp [Output.isError]

/-- For every script whose first statement resolves to a prepare error, its first output is that
error's primary code. Later statements impose no condition. Proof sketch:
{name}`Script.outputOn_eq_step` and {name}`resolvedStepOutput_prepareError`. -/
theorem Script.outputOn_prepareError {script : Script} {db : Database}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {error : PrepareError} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement = .ok (.prepareError error, after)) :
    script.outputOn db = some (.error (ExecutionError.prepare error).primaryCode) := by
  rw [Script.outputOn_eq_step script db statement parameters rest head, resolved]
  change some (resolvedStepOutput none 0 db.raw.connection parameters (.prepareError error)) = _
  rw [resolvedStepOutput_prepareError]

/-- Every query whose statement resolves to a prepare error satisfies {name}`Fails`.
Proof sketch: {name}`Script.outputOn_prepareError` gives an error output. -/
theorem Fails.of_prepareError {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {error : PrepareError} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement = .ok (.prepareError error, after)) :
    Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_prepareError head resolved]
  rfl

/-- Every query with an unmodeled first output satisfies none of {name}`Holds`, {name}`Empty`
or {name}`Fails`. The reason text is arbitrary. Proof sketch: none of the three output tests
accepts {name}`Output.unmodeled`. -/
theorem Script.not_claims_of_unmodeled {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {reason : String} (output : script.outputOn db = some (.unmodeled reason)) :
    ¬ Holds script db isQuery ∧ ¬ Empty script db isQuery ∧ ¬ Fails script db isQuery := by
  simp [Holds, Empty, Fails, output, Output.hasRows, Output.hasNoRows, Output.isError]

/-- For every query resolved without a clock read or unknown counter, if the model's support
check {name}`Resolved.Query.described` is false, none of the three claims holds. This covers a
source or run fault {lean}`Resolved.Fault.may` and a subquery that is not plain. It imposes no
condition on which rows would satisfy the filter. Proof sketch: the common query-output law
produces {name}`Output.unmodeled`, then {name}`Script.not_claims_of_unmodeled` applies. -/
theorem Script.not_claims_query_of_undescribed {script : Script} {db : Database} {isQuery : script.isQuery = true}
    {statement : Syntax.Statement} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {query : Resolved.Query} {subqueries : List Resolved.Query} {after : ResolveState}
    (head : script.statements = (statement, parameters) :: rest)
    (resolved : resolveStatement runContext db.raw.connection.resolveState statement = .ok (.query query subqueries, after))
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : db.raw.connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (undescribed : query.described 0
      (db.raw.connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
      parameters db.raw subqueries = false) :
    ¬ Holds script db isQuery ∧ ¬ Empty script db isQuery ∧ ¬ Fails script db isQuery := by
  apply Script.not_claims_of_unmodeled (reason := unmodeledHere)
  rw [Script.outputOn_query script db statement parameters rest query subqueries after head resolved,
    resolvedStepOutput_query 0 db.raw.connection parameters query subqueries noClock known]
  change query.described 0
    (db.raw.connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
    parameters db.raw.connection.state.database subqueries = false at undescribed
  simp [undescribed]

/-- For every query script whose SELECT has no subqueries, joins, compound or parent, if the
sources resolve, the star check passes, and the body reports a prepare error, {name}`Fails`
holds. The error may come from any body clause, including an unknown column.
Proof sketch: {name}`resolveStatement_select_body_prepareError` gives the prepare error;
{name}`Fails.of_prepareError` gives its observation. -/
theorem Fails.select_body_prepareError {script : Script} {db : Database} {isQuery : script.isQuery = true}
    (query : Syntax.Subquery) (pending : List PendingSource) (scope : Scope) (error : ExprError)
    {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    (head : script.statements = (.select query.columns query.source query.joins query.filter query.groupBy
      query.orderBy query.limit query.offset [] query.having query.distinct query.compound, parameters) :: rest)
    (parent : query.parent = none) (noCompound : query.compound = none) (noJoins : query.joins = [])
    (sourcesOk : resolveSources db.raw.catalog query.source [] = .ok (pending, scope))
    (noStar : starIssue scope query.columns = none)
    (body : resolveQueryBody runContext.profile.dqsDml scope { later := [] } [] pending query = .error (.prepare error)) :
    Fails script db isQuery :=
  Fails.of_prepareError head
    (resolveStatement_select_body_prepareError runContext db.raw.connection.resolveState query pending scope error
      parent noCompound noJoins sourcesOk noStar body)

end Belay.Sqlite
