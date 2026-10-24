import Belay.Sqlite.Model.QueryOutputRows

set_option doc.verso true

/-! The output of a query statement in a run (ADR 0017, S4): a statement that reads no clock and
no unknown counter gives the output of its query ({name}`Belay.Sqlite.Model.Resolved.Query.outputOn`)
when the model describes the statement on the database, and
{name}`Belay.Sqlite.Model.Output.unmodeled` when it does not. -/

namespace Belay.Sqlite.Model

/-- Whether the model describes a query statement on a database, with the counters that it reads: its
subqueries (those that are no term of a compound) have no fallible call, and neither the source
rows nor the run of the query have the fault {name}`Resolved.Fault.may`. It is the support check of
{name}`runStatement` for a query. -/
def Resolved.Query.described (query : Resolved.Query) (clock : Int) (counters : Counters) (parameters : List Value)
    (database : Database) (subqueries : List Resolved.Query) : Bool :=
  Resolved.subqueriesPlain (query.nestedSubqueries subqueries) &&
    (query.runOn clock counters parameters database subqueries).all fun (source, run) =>
      source.fault != .may && run.fault != .may

/-- For every query statement, the output of its step in a run without a clock
({name}`resolvedStepOutput`) is, when the statement reads no clock and no unknown counter, the output
of the query ({name}`Resolved.Query.outputOn`) if the model describes the statement
({name}`Resolved.Query.described`) and {name}`Output.unmodeled` otherwise. The query runs at the clock
value 0 with the counters that it reads. Proof sketch: unfold the step; the clock value of a
statement that reads no clock is 0, and {name}`Output.ofStep_query` gives the output. -/
theorem resolvedStepOutput_query (index : Nat) (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (subqueries : List Resolved.Query)
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none) :
    resolvedStepOutput none index connection parameters (.query query subqueries) =
      if query.described 0 (connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
          parameters connection.state.database subqueries then
        query.outputOn 0 (connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
          parameters connection.state.database subqueries
      else .unmodeled unmodeledHere := by
  unfold resolvedStepOutput
  simp only [statementClock, noClock, Bool.false_eq_true, ite_false, known]
  simp only [SqlState.statementRun, runStatement, Resolved.Query.described, Option.isNone, known]
  by_cases ready : (Resolved.subqueriesPlain (query.nestedSubqueries subqueries) &&
      (query.runOn 0 (connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
        parameters connection.state.database subqueries).all fun (source, run) =>
        source.fault != .may && run.fault != .may) = true
  · simp only [ready, Bool.and_true, Bool.not_true, ite_true]
    exact Output.ofStep_query query subqueries 0 index parameters connection.state _ rfl
  · simp [ready]

/-- The context in which a query statement evaluates its query on the connection, without a clock:
the clock value 0, the counters that the statement reads, the values bound to its parameters, the
database of the connection and the subqueries ({name}`Resolved.statementContext`). -/
abbrev Connection.queryContext (connection : Connection) (parameters : List Value) (query : Resolved.Query)
    (subqueries : List Resolved.Query) : Resolved.EvalContext :=
  Resolved.statementContext 0 (connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
    parameters connection.state.database subqueries

/-- For every query statement whose query has source rows {lit}`source`, the run of the query on the
connection is the run over these rows. Proof sketch: unfold {name}`Resolved.Query.runOn` and rewrite
with the hypothesis {lit}`found`. -/
theorem Connection.runOn_of_found (connection : Connection) (parameters : List Value) (query : Resolved.Query)
    (subqueries : List Resolved.Query) (source : Resolved.SourceRows)
    (found : query.source (connection.queryContext parameters query subqueries) connection.state.database = some source) :
    query.runOn 0 (connection.state.counters.view (Resolved.Statement.query query subqueries).counterReads)
      parameters connection.state.database subqueries =
      some (source, query.run (connection.queryContext parameters query subqueries) source.rows) := by
  simp [Resolved.Query.runOn, found]

/-- A fault that is not {lit}`may` is not {lit}`must` exactly when it is {lit}`none`: the model
describes a query only when its faults are none or {lit}`must`. Proof sketch: case analysis on the
three faults; the case {lit}`may` is excluded by the hypothesis. -/
theorem Resolved.Fault.ne_must_iff_none (fault : Resolved.Fault) (notMay : fault ≠ .may) :
    fault ≠ .must ↔ fault = .none := by
  cases fault <;> simp_all

/-- For every query statement that reads no clock and no unknown counter, whose source rows
{lit}`source` and bound window {lit}`bound` exist, the output of its step has rows exactly when
all of these hold: the subqueries of the query are plain, the source rows have no fault
{lit}`may`, the run of the query has no window mismatch, no overflow and no fault, and the one
result of the bound query has a row. Proof sketch: {name}`resolvedStepOutput_query` and
{name}`Resolved.Query.outputOn_hasRows`; the model describes a run only when its fault is not
{lit}`may`, and a fault that is neither {lit}`may` nor {lit}`must` is none
({name}`Resolved.Fault.ne_must_iff_none`). -/
theorem resolvedStepOutput_query_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (query bound : Resolved.Query) (subqueries : List Resolved.Query) (source : Resolved.SourceRows)
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (connection.queryContext parameters query subqueries) connection.state.database = some source)
    (window : query.bindWindow parameters = some bound) :
    (resolvedStepOutput none index connection parameters (.query query subqueries)).hasRows = true ↔
      Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true ∧ source.fault ≠ .may ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).mismatch = false ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).overflow = false ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .none ∧
        bound.results (connection.queryContext parameters query subqueries) source.rows ≠ [] := by
  rw [resolvedStepOutput_query index connection parameters query subqueries noClock known]
  have hrun := connection.runOn_of_found parameters query subqueries source found
  unfold Resolved.Query.described
  rw [hrun]
  by_cases plain : Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true
  · by_cases srcFault : source.fault = .may
    · simp [plain, srcFault, Output.hasRows]
    · by_cases runFault : (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .may
      · simp [plain, runFault, Output.hasRows]
      · simp [plain, srcFault, runFault, Resolved.Fault.ne_must_iff_none _ runFault, Resolved.Query.outputOn_hasRows _ _ _ _ _ _ _ _ found window]
  · simp [plain, Output.hasRows]

/-- For every query statement that reads no clock and no unknown counter, whose source rows
{lit}`source` and bound window {lit}`bound` exist, the output of its step has no rows exactly when
all of these hold: the subqueries of the query are plain, the source rows have no fault
{lit}`may`, the run of the query has no window mismatch, no overflow and no fault, and the one
result of the bound query has no row. Proof sketch: {name}`resolvedStepOutput_query` and
{name}`Resolved.Query.outputOn_hasNoRows`; the model describes a run only when its fault is not
{lit}`may`, and a fault that is neither {lit}`may` nor {lit}`must` is none
({name}`Resolved.Fault.ne_must_iff_none`). -/
theorem resolvedStepOutput_query_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (query bound : Resolved.Query) (subqueries : List Resolved.Query) (source : Resolved.SourceRows)
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (connection.queryContext parameters query subqueries) connection.state.database = some source)
    (window : query.bindWindow parameters = some bound) :
    (resolvedStepOutput none index connection parameters (.query query subqueries)).hasNoRows = true ↔
      Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true ∧ source.fault ≠ .may ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).mismatch = false ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).overflow = false ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .none ∧
        bound.results (connection.queryContext parameters query subqueries) source.rows = [] := by
  rw [resolvedStepOutput_query index connection parameters query subqueries noClock known]
  have hrun := connection.runOn_of_found parameters query subqueries source found
  unfold Resolved.Query.described
  rw [hrun]
  by_cases plain : Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true
  · by_cases srcFault : source.fault = .may
    · simp [plain, srcFault, Output.hasNoRows]
    · by_cases runFault : (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .may
      · simp [plain, runFault, Output.hasNoRows]
      · simp [plain, srcFault, runFault, Resolved.Fault.ne_must_iff_none _ runFault, Resolved.Query.outputOn_hasNoRows _ _ _ _ _ _ _ _ found window]
  · simp [plain, Output.hasNoRows]


/-- For every query statement that reads no clock and no unknown counter, whose source rows
{lit}`source` exist, the output of its step is an error exactly when the model describes the statement
and the run has a window mismatch, an overflow or a failing function. Proof sketch:
{name}`resolvedStepOutput_query` and {name}`Resolved.Query.outputOn_isError`; an output that is
{name}`Output.unmodeled` is no error. -/
theorem resolvedStepOutput_query_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (subqueries : List Resolved.Query) (source : Resolved.SourceRows)
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (connection.queryContext parameters query subqueries) connection.state.database = some source) :
    (resolvedStepOutput none index connection parameters (.query query subqueries)).isError = true ↔
      Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true ∧ source.fault ≠ .may ∧
        (query.run (connection.queryContext parameters query subqueries) source.rows).fault ≠ .may ∧
        ((query.run (connection.queryContext parameters query subqueries) source.rows).mismatch = true ∨
        (query.run (connection.queryContext parameters query subqueries) source.rows).overflow = true ∨
        (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .must) := by
  rw [resolvedStepOutput_query index connection parameters query subqueries noClock known]
  have hrun := connection.runOn_of_found parameters query subqueries source found
  unfold Resolved.Query.described
  rw [hrun]
  by_cases plain : Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = true
  · by_cases srcFault : source.fault = .may
    · simp [plain, srcFault, Output.isError]
    · by_cases runFault : (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .may
      · simp [plain, runFault, Output.isError]
      · simp [plain, srcFault, runFault, Resolved.Query.outputOn_isError _ _ _ _ _ _ _ found]
  · simp [plain, Output.isError]

end Belay.Sqlite.Model
