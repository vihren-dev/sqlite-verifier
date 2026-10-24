import Belay.Sqlite.Model.QueryOutputCases
import Belay.Sqlite.Model.OutputResultsLaws
import Belay.Sqlite.Model.PossibleResultsLaws

set_option doc.verso true

/-! When the output of a query has rows, has no rows, or is an error (ADR 0017, S4): in terms of
the source rows of the query, its run over them, and its one result
({name}`Belay.Sqlite.Model.Resolved.Query.results`). Every result that SQLite may give for a
query has as many rows as that one result, so the output has rows exactly when the one result has a
row. -/

namespace Belay.Sqlite.Model

/-- For every query, context and source rows, the output of the results that SQLite may give has
rows ({name}`Output.hasRows`) exactly when the one result of the query ({name}`Resolved.Query.results`)
has a row. Proof sketch: SQLite may give at least one result ({name}`Resolved.Query.possibleResults_ne_nil`),
and each result has the length of the one result ({name}`Resolved.Query.possibleResults_length`). -/
theorem Output.hasRows_possibleResults (context : Resolved.EvalContext) (query : Resolved.Query)
    (rows : List (List Value)) :
    (Output.ofResults (query.possibleResults context rows)).hasRows = true ↔ query.results context rows ≠ [] := by
  rw [Output.hasRows_ofResults]
  constructor
  · rintro ⟨nonempty, each⟩ none
    obtain ⟨result, member⟩ := List.exists_mem_of_ne_nil _ nonempty
    have length := Resolved.Query.possibleResults_length context query rows result member
    rw [none] at length
    exact each result member (List.eq_nil_of_length_eq_zero length)
  · intro nonempty
    refine ⟨Resolved.Query.possibleResults_ne_nil context query rows, fun result member => ?_⟩
    have length := Resolved.Query.possibleResults_length context query rows result member
    intro empty
    rw [empty] at length
    exact nonempty (List.eq_nil_of_length_eq_zero length.symm)

/-- For every query, context and source rows, the output of the results that SQLite may give has no
rows ({name}`Output.hasNoRows`) exactly when the one result of the query has no row. Proof sketch: as
{name}`Output.hasRows_possibleResults`. -/
theorem Output.hasNoRows_possibleResults (context : Resolved.EvalContext) (query : Resolved.Query)
    (rows : List (List Value)) :
    (Output.ofResults (query.possibleResults context rows)).hasNoRows = true ↔ query.results context rows = [] := by
  rw [Output.hasNoRows_ofResults]
  constructor
  · rintro ⟨nonempty, each⟩
    obtain ⟨result, member⟩ := List.exists_mem_of_ne_nil _ nonempty
    have length := Resolved.Query.possibleResults_length context query rows result member
    rw [each result member] at length
    exact List.eq_nil_of_length_eq_zero length.symm
  · intro empty
    refine ⟨Resolved.Query.possibleResults_ne_nil context query rows, fun result member => ?_⟩
    have length := Resolved.Query.possibleResults_length context query rows result member
    rw [empty] at length
    exact List.eq_nil_of_length_eq_zero length

/-- For every query and statement data whose query has source rows {lit}`source` and a bound window
{lit}`bound`, the output of the query has rows exactly when the run has no window mismatch, no
overflow and no failing function, and the one result of the bound query has a row. Proof sketch:
the three cases of an error give an error output, which has no rows; the last case is
{name}`Resolved.Query.outputOn_clean` and {name}`Output.hasRows_possibleResults`. -/
theorem Resolved.Query.outputOn_hasRows (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows) (bound : Resolved.Query)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source)
    (window : query.bindWindow parameters = some bound) :
    (query.outputOn clock counters parameters database subqueries).hasRows = true ↔
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false ∧
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = false ∧
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault ≠ .must ∧
      bound.results (Resolved.statementContext clock counters parameters database subqueries) source.rows ≠ [] := by
  by_cases mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = true
  · rw [Resolved.Query.outputOn_mismatch query clock counters parameters database subqueries source found mismatch]
    simp [Output.hasRows, mismatch]
  have mismatch' : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false := by
    simpa using mismatch
  by_cases overflow : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = true
  · rw [Resolved.Query.outputOn_overflow query clock counters parameters database subqueries source found mismatch' overflow]
    simp [Output.hasRows, mismatch', overflow]
  have overflow' : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = false := by
    simpa using overflow
  by_cases fault : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault = .must
  · rw [Resolved.Query.outputOn_function query clock counters parameters database subqueries source found mismatch' overflow' fault]
    simp [Output.hasRows, mismatch', overflow', fault]
  rw [Resolved.Query.outputOn_clean query clock counters parameters database subqueries source bound found window mismatch' overflow' fault,
    Output.hasRows_possibleResults]
  simp [mismatch', overflow', fault]

/-- For every query and statement data whose query has source rows {lit}`source` and a bound window
{lit}`bound`, the output of the query has no rows exactly when the run has no window mismatch, no
overflow and no failing function, and the one result of the bound query has no row. Proof sketch:
the three cases of an error give an error output, which is no output without rows; the last case is
{name}`Resolved.Query.outputOn_clean` and {name}`Output.hasNoRows_possibleResults`. -/
theorem Resolved.Query.outputOn_hasNoRows (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows) (bound : Resolved.Query)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source)
    (window : query.bindWindow parameters = some bound) :
    (query.outputOn clock counters parameters database subqueries).hasNoRows = true ↔
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false ∧
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = false ∧
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault ≠ .must ∧
      bound.results (Resolved.statementContext clock counters parameters database subqueries) source.rows = [] := by
  by_cases mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = true
  · rw [Resolved.Query.outputOn_mismatch query clock counters parameters database subqueries source found mismatch]
    simp [Output.hasNoRows, mismatch]
  have mismatch' : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false := by
    simpa using mismatch
  by_cases overflow : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = true
  · rw [Resolved.Query.outputOn_overflow query clock counters parameters database subqueries source found mismatch' overflow]
    simp [Output.hasNoRows, mismatch', overflow]
  have overflow' : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = false := by
    simpa using overflow
  by_cases fault : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault = .must
  · rw [Resolved.Query.outputOn_function query clock counters parameters database subqueries source found mismatch' overflow' fault]
    simp [Output.hasNoRows, mismatch', overflow', fault]
  rw [Resolved.Query.outputOn_clean query clock counters parameters database subqueries source bound found window mismatch' overflow' fault,
    Output.hasNoRows_possibleResults]
  simp [mismatch', overflow', fault]


/-- For every query and statement data whose query has source rows {lit}`source`, the output of the
query is an error ({name}`Output.isError`) exactly when the run has a window mismatch, an overflow
or a failing function. Proof sketch: the three error cases are {name}`Resolved.Query.outputOn_mismatch`,
{name}`Resolved.Query.outputOn_overflow` and {name}`Resolved.Query.outputOn_function`; in the last
case the bound window gives rows, which are no error ({name}`Output.isError_ofResults`), and a missing bound window
gives {name}`Output.unmodeled`, which is no error either. -/
theorem Resolved.Query.outputOn_isError (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source) :
    (query.outputOn clock counters parameters database subqueries).isError = true ↔
      ((query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = true ∨
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = true ∨
      (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault = .must) := by
  unfold Resolved.Query.outputOn Resolved.Query.runOn
  simp only [found]
  by_cases mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = true
  · simp [mismatch, Output.isError]
  by_cases overflow : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = true
  · simp [mismatch, overflow, Output.isError]
  by_cases fault : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault = .must
  · simp [mismatch, overflow, fault, Output.isError]
  have mismatch' := Bool.eq_false_iff.mpr mismatch
  have overflow' := Bool.eq_false_iff.mpr overflow
  rcases query.possibleOn clock counters parameters database subqueries with _ | results
  · simp [mismatch', overflow', fault, Output.isError]
  · have noError := Output.isError_ofResults results
    simp [mismatch', overflow', fault, noError]

end Belay.Sqlite.Model
