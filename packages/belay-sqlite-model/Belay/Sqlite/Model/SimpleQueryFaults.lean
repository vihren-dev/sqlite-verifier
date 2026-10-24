import Belay.Sqlite.Model.SimpleQuerySteps
import Belay.Sqlite.Model.StatementQuiet

set_option doc.verso true

/-! Simple query observations with fallible scalar functions. The query's fault remains
explicit, so a known function error and an uncertain failure cannot become a row claim. -/

namespace Belay.Sqlite.Model

/-- For every quiet scalar expression and quiet optional condition, the no-FROM SELECT
of that scalar is quiet, for any output names. Proof sketch: its expressions are exactly
the condition and scalar expression. -/
theorem Resolved.Statement.Quiet.selectNoFrom (condition : Option Resolved.Expr) (expression : Resolved.Expr) (names : List String)
    (conditionQuiet : ∀ part ∈ condition.toList, part.Quiet) (quiet : expression.Quiet) :
    (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Quiet := by
  intro part member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.expressions, Resolved.Query.keptExpressions,
    Resolved.Query.simple, List.mem_append, List.flatMap_nil, Resolved.Output.scalars, Resolved.Output.operands,
    List.mem_singleton, List.map_nil, List.append_nil, List.flatMap_cons, Option.toList_none] at member
  rcases member with member | member
  · exact conditionQuiet part member
  · rw [member]
    exact quiet

/-- Every simple query binds its window without a mismatch, for every context and source rows.
Proof sketch: a simple query has no window parameters or compound. -/
theorem Resolved.Query.Simple.run_mismatch {query : Resolved.Query} (simple : query.Simple)
    (context : Resolved.EvalContext) (rows : List (List Value)) :
    (query.run context rows).mismatch = false := by
  simp [Resolved.Query.run, simple.compound, simple.bindWindow]

/-- Every simple query has no aggregate overflow, for every context and source rows. Scalar
function faults are separate from this flag. Proof sketch: the query binds its window and is
not an aggregate query. -/
theorem Resolved.Query.Simple.run_overflow {query : Resolved.Query} (simple : query.Simple)
    (context : Resolved.EvalContext) (rows : List (List Value)) :
    (query.run context rows).overflow = false := by
  simp [Resolved.Query.run, simple.compound, simple.bindWindow, Resolved.Query.fails, simple.aggregate]

/-- For every quiet simple query without subqueries, with available source rows whose source
fault is none, its step has rows exactly when the run's fault is none and a source row passes
its filter. With no filter every source row passes. A may-fault or must-fault makes the claim
false. Proof sketch: the common query observation, the simple window/overflow laws, and the
simple result-membership law. -/
theorem resolvedStepOutput_simple_fault_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (simple : query.Simple) (source : Resolved.SourceRows)
    (quiet : (Resolved.Statement.query query []).Quiet)
    (found : query.source (connection.queryContext parameters query []) connection.state.database = some source)
    (clean : source.fault = .none) :
    (resolvedStepOutput none index connection parameters (.query query [])).hasRows = true ↔
      (query.run (connection.queryContext parameters query []) source.rows).fault = .none ∧
      ∃ row ∈ source.rows, query.filter.all
        (fun expression => Resolved.truthy (expression.eval (connection.queryContext parameters query []) row)) = true := by
  rw [resolvedStepOutput_query_hasRows index connection parameters query query [] source quiet.readsClock
    (quiet.firstUnknown _) found (simple.bindWindow parameters), simple.run_mismatch, simple.run_overflow,
    simple.results_ne_nil_iff]
  simp [Resolved.subqueriesPlain, Resolved.Query.nestedSubqueries, simple.compound, clean]

/-- Under the hypotheses of {name}`resolvedStepOutput_simple_fault_hasRows`, the step has no
rows exactly when its run has no fault and no source row passes its filter. An empty source
satisfies the filter condition without further requirements. Proof sketch: the common empty
observation and the simple result-emptiness law. -/
theorem resolvedStepOutput_simple_fault_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (simple : query.Simple) (source : Resolved.SourceRows)
    (quiet : (Resolved.Statement.query query []).Quiet)
    (found : query.source (connection.queryContext parameters query []) connection.state.database = some source)
    (clean : source.fault = .none) :
    (resolvedStepOutput none index connection parameters (.query query [])).hasNoRows = true ↔
      (query.run (connection.queryContext parameters query []) source.rows).fault = .none ∧
      ∀ row ∈ source.rows, query.filter.all
        (fun expression => Resolved.truthy (expression.eval (connection.queryContext parameters query []) row)) = false := by
  rw [resolvedStepOutput_query_hasNoRows index connection parameters query query [] source quiet.readsClock
    (quiet.firstUnknown _) found (simple.bindWindow parameters), simple.run_mismatch, simple.run_overflow,
    simple.results_eq_nil_iff]
  simp [Resolved.subqueriesPlain, Resolved.Query.nestedSubqueries, simple.compound, clean]

/-- Under the hypotheses of {name}`resolvedStepOutput_simple_fault_hasRows`, the step is an
error exactly when its run has a must-fault. A may-fault is unmodeled and is not an error
observation. Proof sketch: the common error observation; a simple query has neither window
mismatch nor aggregate overflow. -/
theorem resolvedStepOutput_simple_fault_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (simple : query.Simple) (source : Resolved.SourceRows)
    (quiet : (Resolved.Statement.query query []).Quiet)
    (found : query.source (connection.queryContext parameters query []) connection.state.database = some source)
    (clean : source.fault = .none) :
    (resolvedStepOutput none index connection parameters (.query query [])).isError = true ↔
      (query.run (connection.queryContext parameters query []) source.rows).fault = .must := by
  rw [resolvedStepOutput_query_isError index connection parameters query [] source quiet.readsClock
    (quiet.firstUnknown _) found, simple.run_mismatch, simple.run_overflow]
  simp [Resolved.subqueriesPlain, Resolved.Query.nestedSubqueries, simple.compound, clean]
  intro must
  simp [must]

end Belay.Sqlite.Model
