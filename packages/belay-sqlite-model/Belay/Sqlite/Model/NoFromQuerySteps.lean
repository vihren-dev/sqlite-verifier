import Belay.Sqlite.Model.SimpleQuerySteps
import Belay.Sqlite.Model.QueryJoinLaws

set_option doc.verso true

/-! The output of a simple query without {lit}`FROM` (ADR 0017, S4): {lit}`SELECT e WHERE c`, with any
subqueries. The query reads one row with no cells, so its output has a row exactly when {lit}`WHERE` is
true for that row, has no row exactly when it is not, and is never an error, if the statement is
calm and its expressions have no fault over the row. -/

namespace Belay.Sqlite.Model

/-- The query {lit}`SELECT 1 WHERE c` of a resolved condition {lit}`c`: it has no source, the one result
column {lit}`1` named {lit}`"1"`, and no other clause. -/
abbrev Resolved.Query.selectOneWhere (condition : Resolved.Expr) : Resolved.Query :=
  Resolved.Query.simple [] (some condition) [.scalar (.literal (.integer 1))] ["1"]

/-- The expressions of {lit}`SELECT 1 WHERE c` are the condition and the literal 1. Proof sketch: the
definitions compute. -/
theorem Resolved.Query.selectOneWhere_expressions (condition : Resolved.Expr) :
    (Resolved.Query.selectOneWhere condition).expressions = [condition, .literal (.integer 1)] := rfl

/-- For every context and condition whose evaluation over the row with no cells has no fault, every
expression of {lit}`SELECT 1 WHERE c` has none: the condition, and the literal 1. Proof sketch:
{name}`Resolved.Query.selectOneWhere_expressions`; a literal has no fault. -/
theorem Resolved.Query.selectOneWhere_faultless (context : Resolved.EvalContext) (condition : Resolved.Expr)
    (none : (condition.evaluate context []).2 = .none) :
    ∀ expression ∈ (Resolved.Query.selectOneWhere condition).expressions, (expression.evaluate context []).2 = .none := by
  intro expression member
  rw [Resolved.Query.selectOneWhere_expressions] at member
  rcases List.mem_cons.mp member with rfl | member
  · exact none
  · simp only [List.mem_singleton] at member
    subst member
    rfl

/-- For every connection, values, condition, result columns, names and subqueries, where the statement of the
simple query without {lit}`FROM` is calm and its expressions have no fault over the row with no cells in the
context of the statement, the output of the step has rows exactly when the condition, if any, is true for
the row with no cells. Proof sketch: {name}`resolvedStepOutput_simple_hasRows_of_faultless` with the source of a
query without {lit}`FROM` ({name}`Resolved.Query.source_none`), the one row with no cells. -/
theorem resolvedStepOutput_noFrom_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (subqueries : List Resolved.Query)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [] condition columns names) subqueries).Calm)
    (faultless : ∀ expression ∈ (Resolved.Query.simple [] condition columns names).expressions,
      (expression.evaluate (connection.queryContext parameters (Resolved.Query.simple [] condition columns names) subqueries)
        []).2 = .none) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [] condition columns names) subqueries)).hasRows = true ↔
      condition.all (fun expression => Resolved.truthy (expression.eval
        (connection.queryContext parameters (Resolved.Query.simple [] condition columns names) subqueries) [])) = true := by
  rw [resolvedStepOutput_simple_hasRows_of_faultless index connection parameters _ subqueries
    (Resolved.Query.simple_isSimple _ _ _ _) { rows := [[]], width := 0, fault := .none } calm
    (Resolved.Query.source_none _ _ _ rfl) rfl (fun row member expression inside => by
      have : row = [] := by simpa using member
      subst this
      exact faultless expression inside)]
  simp [Resolved.Query.simple]

/-- For every connection, values, condition, result columns, names and subqueries as in
{name}`resolvedStepOutput_noFrom_hasRows`, the output of the step has no rows exactly when the condition,
if any, is not true for the row with no cells. Proof sketch: as for
{name}`resolvedStepOutput_noFrom_hasRows`, with {name}`resolvedStepOutput_simple_hasNoRows_of_faultless`. -/
theorem resolvedStepOutput_noFrom_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (subqueries : List Resolved.Query)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [] condition columns names) subqueries).Calm)
    (faultless : ∀ expression ∈ (Resolved.Query.simple [] condition columns names).expressions,
      (expression.evaluate (connection.queryContext parameters (Resolved.Query.simple [] condition columns names) subqueries)
        []).2 = .none) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [] condition columns names) subqueries)).hasNoRows = true ↔
      condition.all (fun expression => Resolved.truthy (expression.eval
        (connection.queryContext parameters (Resolved.Query.simple [] condition columns names) subqueries) [])) = false := by
  rw [resolvedStepOutput_simple_hasNoRows_of_faultless index connection parameters _ subqueries
    (Resolved.Query.simple_isSimple _ _ _ _) { rows := [[]], width := 0, fault := .none } calm
    (Resolved.Query.source_none _ _ _ rfl) rfl (fun row member expression inside => by
      have : row = [] := by simpa using member
      subst this
      exact faultless expression inside)]
  simp [Resolved.Query.simple]

/-- For every connection, values, condition, result columns, names and subqueries as in
{name}`resolvedStepOutput_noFrom_hasRows`, the output of the step is no error. Proof sketch:
{name}`resolvedStepOutput_simple_not_isError_of_faultless` with the source of a query without
{lit}`FROM`. -/
theorem resolvedStepOutput_noFrom_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (subqueries : List Resolved.Query)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [] condition columns names) subqueries).Calm)
    (faultless : ∀ expression ∈ (Resolved.Query.simple [] condition columns names).expressions,
      (expression.evaluate (connection.queryContext parameters (Resolved.Query.simple [] condition columns names) subqueries)
        []).2 = .none) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [] condition columns names) subqueries)).isError = false :=
  resolvedStepOutput_simple_not_isError_of_faultless index connection parameters _ subqueries
    (Resolved.Query.simple_isSimple _ _ _ _) { rows := [[]], width := 0, fault := .none } calm
    (Resolved.Query.source_none _ _ _ rfl) (fun row member expression inside => by
      have : row = [] := by simpa using member
      subst this
      exact faultless expression inside)

end Belay.Sqlite.Model
