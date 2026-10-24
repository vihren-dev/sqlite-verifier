import Belay.Sqlite.Model.DuplicateKeyQuery
import Belay.Sqlite.Model.NotExistsSubqueryOutput

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t GROUP BY k HAVING count(*) > 1)` (ADR 0017, S4):
a statement without {lit}`FROM` and with one subquery, the duplicate-key query of one table
({name}`Belay.Sqlite.Model.Resolved.Query.duplicateKeys`). The subquery gives a row for each group of more than one
row, so the statement has rows exactly when every group of the table has one row at most. -/

namespace Belay.Sqlite.Model

/-- The expressions of the duplicate-key query of the first source of a table are the literal one, the grouping
key, and the condition {lit}`count(*) > 1`. Proof sketch: the definitions compute. -/
theorem Resolved.Query.duplicateKeys_first_expressions (position : Nat) (key : Resolved.Expr) (collation : Collation) :
    (Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation).expressions =
      [.literal (.integer 1), key,
        .compare .gt none (.aggregateValue 0) (.literal (.integer 1)) .binary] := by
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.duplicateKeys,
    Resolved.QuerySource.first, Resolved.QuerySource.expressions, Resolved.Output.scalars, Resolved.Output.operands]

/-- The condition {lit}`count(*) > 1` is calm: it has no fallible call, no clock read and no counter read. Proof
sketch: it is a comparison of an aggregate value and a literal. -/
theorem Resolved.Expr.calm_moreThanOne :
    (Resolved.Expr.compare .gt none (.aggregateValue 0) (.literal (.integer 1)) .binary).Calm := by
  simp [Resolved.Expr.Calm, Resolved.Expr.any, Resolved.Expr.isFallibleCall, Resolved.Expr.readsClockHere,
    Resolved.Expr.readsCounterHere]

/-- For every calm condition {lit}`c` and calm key, the statement of {lit}`SELECT 1 WHERE c` with the duplicate-key
query of the first source of a table as its one subquery is calm ({name}`Resolved.Statement.Calm`). Proof sketch: the
expressions of the statement are the condition, the literal one, and the expressions of the subquery
({name}`Resolved.Query.duplicateKeys_first_expressions`). -/
theorem Resolved.Statement.Calm.selectOne_duplicateKeys (position : Nat) (main key : Resolved.Expr)
    (collation : Collation) (mainCalm : main.Calm) (keyCalm : key.Calm) :
    (Resolved.Statement.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation]).Calm := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions,
    Resolved.Query.duplicateKeys_first_expressions, List.flatMap_cons, List.flatMap_nil, List.append_nil,
    List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with (rfl | rfl) | rfl | rfl | rfl
  · exact mainCalm
  · exact Resolved.Expr.calm_literal _
  · exact Resolved.Expr.calm_literal _
  · exact keyCalm
  · exact Resolved.Expr.calm_moreThanOne

/-- For every connection, values, query and calm statement of the query with one subquery that is the duplicate-key
query of the table at a position of the database, subquery 0 of the context for the outer row with no cells has the
result rows of the duplicate-key query over the rows of the table in scan order as its rows, no fault and certain rows.
Proof sketch: {name}`Connection.queryContext_subquery_zero` and {name}`Resolved.Query.duplicateKeys_subqueryRun` with the
source rows of {name}`Resolved.Query.source_first`; the context is quiet, so no expression has a fault. -/
theorem Connection.queryContext_duplicateKeys_zero (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (position : Nat) (table : Table) (key : Resolved.Expr) (collation : Collation)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query query
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation]).Calm) :
    (connection.queryContext parameters query
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation]).subqueries 0 [] =
      { rows := (Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation).results
          (Resolved.EvalContext.bound parameters) (Resolved.sourceRows table),
        fault := .none,
        firstCertain := (Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation).windowCertain
          (Resolved.EvalContext.bound parameters) (Resolved.sourceRows table) (some 1),
        rowsCertain := true, ending := .done } := by
  have plain := calm.subquery_plain (List.mem_singleton_self _)
  rw [connection.queryContext_subquery_zero parameters query _ calm]
  refine Resolved.Query.duplicateKeys_subqueryRun _ _ _ _ _ _
    (Resolved.Query.source_first _ _ _ position table rfl present) rfl plain fun row _ expression member => ?_
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  exact Resolved.Expr.fault_of_plain _ (Resolved.EvalContext.bound_quiet parameters) row expression (plain expression member)

/-- For every connection, values, table at a position of the database, key, collation and calm statement of
{lit}`SELECT 1 WHERE NOT EXISTS (q)` with the duplicate-key query of that table as its subquery, the output of the
step has rows exactly when no group of the rows of the table, grouped by the key under the collation
({name}`Resolved.groups`), has more than one row. Proof sketch: {name}`resolvedStepOutput_noFrom_hasRows`; the value of
{lit}`NOT EXISTS` is true when the subquery has no row ({name}`Connection.queryContext_duplicateKeys_zero`), which is
the case exactly when no group has more than one row ({name}`Resolved.Query.duplicateKeys_results`). -/
theorem resolvedStepOutput_notExists_duplicateKeys_hasRows (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (key : Resolved.Expr) (collation : Collation)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation])).hasRows = true ↔
      ∀ group ∈ Resolved.groups (Resolved.EvalContext.bound parameters) [(key, collation)] (Resolved.sourceRows table),
        group.length ≤ 1 := by
  have run := connection.queryContext_duplicateKeys_zero parameters _ position table key collation present calm
  rw [resolvedStepOutput_noFrom_hasRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_not, Resolved.Expr.fault_exists, run]))]
  simp only [Option.all_some, Resolved.Expr.eval_not, Resolved.Expr.eval_exists, Resolved.truthy_not, run,
    Resolved.falsy, truthy_truth, isNull_truth, Bool.not_false, Bool.true_and, Bool.not_not, List.isEmpty_iff,
    Resolved.Query.duplicateKeys_results, List.map_eq_nil_iff, List.filter_eq_nil_iff, decide_eq_true_eq]
  exact ⟨fun every group member => Nat.not_lt.mp (every group member), fun every group member => Nat.not_lt.mpr (every group member)⟩

/-- For every connection, values, table, key, collation and calm statement as in
{name}`resolvedStepOutput_notExists_duplicateKeys_hasRows`, the output of the step has no rows exactly when some
group of the rows of the table, grouped by the key under the collation, has more than one row. Proof sketch: as for
{name}`resolvedStepOutput_notExists_duplicateKeys_hasRows`, with {name}`resolvedStepOutput_noFrom_hasNoRows`. -/
theorem resolvedStepOutput_notExists_duplicateKeys_hasNoRows (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (key : Resolved.Expr) (collation : Collation)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation])).hasNoRows = true ↔
      ∃ group ∈ Resolved.groups (Resolved.EvalContext.bound parameters) [(key, collation)] (Resolved.sourceRows table),
        1 < group.length := by
  have run := connection.queryContext_duplicateKeys_zero parameters _ position table key collation present calm
  rw [resolvedStepOutput_noFrom_hasNoRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_not, Resolved.Expr.fault_exists, run]))]
  simp only [Option.all_some, Resolved.Expr.eval_not, Resolved.Expr.eval_exists, Resolved.truthy_not, run,
    Resolved.falsy, truthy_truth, isNull_truth, Bool.not_false, Bool.true_and, Bool.not_not,
    List.isEmpty_eq_false_iff, Resolved.Query.duplicateKeys_results, ne_eq, List.map_eq_nil_iff, List.filter_eq_nil_iff,
    decide_eq_true_eq]
  constructor
  · intro notAll
    exact Classical.byContradiction fun none => notAll fun group member long => none ⟨group, member, long⟩
  · rintro ⟨group, member, long⟩ every
    exact every group member long

/-- For every connection, values, table, key, collation and calm statement as in
{name}`resolvedStepOutput_notExists_duplicateKeys_hasRows`, the output of the step is no error. Proof sketch:
{name}`resolvedStepOutput_noFrom_not_isError`, with the fault of the subquery from
{name}`Connection.queryContext_duplicateKeys_zero`. -/
theorem resolvedStepOutput_notExists_duplicateKeys_not_isError (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (key : Resolved.Expr) (collation : Collation)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation])).isError = false := by
  have run := connection.queryContext_duplicateKeys_zero parameters _ position table key collation present calm
  exact resolvedStepOutput_noFrom_not_isError index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_not, Resolved.Expr.fault_exists, run]))

end Belay.Sqlite.Model
