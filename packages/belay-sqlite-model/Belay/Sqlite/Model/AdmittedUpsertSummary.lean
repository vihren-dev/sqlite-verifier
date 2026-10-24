import Belay.Sqlite.Model.AdmittedInsertRows
import Belay.Sqlite.Model.AdmittedPlainWrites
import Belay.Sqlite.Model.AdmittedUpsertRows

set_option doc.verso true

/-! The rows of an upsert and the table atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4). An
INSERT with {lit}`ON CONFLICT` clauses or conflict algorithms stores the table that the last reached
row left, or the table before the failed row ({lit}`LiteralData.upsertSummary`). So an atom holds for
that table when each row keeps it. {lit}`upsertSummary_atom` is the induction over the rows, and the
laws for one row read the atom from {lit}`LiteralData.UpsertOrigin`. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every atom of tables, context, keys, policy and clauses, and every test of the queue of rows
still to run ({lit}`queued`): if each row that runs from a table with the atom and the test, and
succeeds, leaves a table with the same entry, the atom, and the test for the rest of the queue (the
step), then the {name}`upsertSummary` of the {name}`upsertSteps` of a queue with the test over a table with
the atom has the atom, with the same entry. The table is the final table when the rows succeed, and the
table before the failed row when a row fails. Proof sketch: induction on the queue; a row that fails
leaves the table, and a row that succeeds leaves a table to which the step and the induction apply. -/
theorem upsertSummary_atom {atom : Table → Prop} (context : Resolved.EvalContext) (keys : List UniqueKey)
    (policy : Resolved.ConflictPolicy) (clauses : List Resolved.ConflictClause)
    (queued : List (List Value) → Table → Prop)
    (step : ∀ (table next : Table) (values : List Value) (rest : List (List Value)) (written : Option Row),
      atom table → queued (values :: rest) table →
      upsertRow context keys policy clauses table values = .ok (next, written) →
      next.shape = table.shape ∧ atom next ∧ queued rest next) :
    ∀ (queue : List (List Value)) (table : Table), atom table → queued queue table →
      match upsertSummary table (upsertSteps context keys policy clauses table queue) with
      | .ok (final, _) => final.shape = table.shape ∧ atom final
      | .error (_, reached, _) => reached.shape = table.shape ∧ atom reached
  | [], _, holds, _ => ⟨rfl, holds⟩
  | values :: rest, table, holds, ahead => by
    simp only [upsertSteps, upsertSummary]
    cases result : upsertRow context keys policy clauses table values with
    | error reason => exact ⟨rfl, holds⟩
    | ok pair =>
      obtain ⟨next, written⟩ := pair
      have kept := step table next values rest written holds ahead result
      have later := upsertSummary_atom context keys policy clauses queued step rest next kept.2.1 kept.2.2
      dsimp only
      rcases summary : upsertSummary next (upsertSteps context keys policy clauses next rest) with
        ⟨_, _, _⟩ | ⟨_, _⟩ <;> simp only [summary] at later ⊢ <;> exact ⟨later.1.trans kept.1, later.2⟩

/-- For every context, keys, policy, clauses, tables, values and written row: a successful
{name}`upsertRow` gives a table with the same entry. Proof sketch: the table is kept, or it has the entry
({name}`upsertRow_cases`). -/
theorem upsertRow_shape {context : Resolved.EvalContext} {keys : List UniqueKey} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {table next : Table} {values : List Value} {written : Option Row}
    (run : upsertRow context keys policy clauses table values = .ok (next, written)) : next.shape = table.shape := by
  rcases upsertRow_cases run with same | ⟨shape, _, _⟩
  · subst same; rfl
  · exact shape

/-- For every row test, table, supplied cells and result: if each row of the table passes the test for the
entry of the table, and each origin of a row ({name}`UpsertOrigin`) passes it, a successful
{name}`upsertRow` gives a table with the same entry whose rows pass the test. Proof sketch: the table is
kept, or each of its rows has an origin ({name}`upsertRow_cases`). -/
theorem upsertRow_rowsOk (ok : CatalogTable → Row → Prop) {context : Resolved.EvalContext} {keys : List UniqueKey}
    {policy : Resolved.ConflictPolicy} {clauses : List Resolved.ConflictClause} {table next : Table}
    {values : List Value} {written : Option Row} (good : ∀ row ∈ table.rows, ok table.shape row)
    (origin : ∀ row, UpsertOrigin context clauses table (proposedRow table values) row → ok table.shape row)
    (run : upsertRow context keys policy clauses table values = .ok (next, written)) :
    next.shape = table.shape ∧ ∀ row ∈ next.rows, ok next.shape row := by
  rcases upsertRow_cases run with same | ⟨shape, _, rows⟩
  · subst same
    exact ⟨rfl, good⟩
  · exact ⟨shape, fun row member => by rw [shape]; exact origin row (rows row member)⟩

/-- For every table with distinct rowids and a successful {name}`upsertRow`: the table has the same entry and
distinct rowids. Proof sketch: the table is kept, or it passed {name}`rowidsDistinct`
({name}`upsertRow_cases`). -/
theorem upsertRow_distinct {context : Resolved.EvalContext} {keys : List UniqueKey} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {table next : Table} {values : List Value} {written : Option Row}
    (distinct : table.RowidsDistinct) (run : upsertRow context keys policy clauses table values = .ok (next, written)) :
    next.shape = table.shape ∧ next.RowidsDistinct := by
  rcases upsertRow_cases run with same | ⟨shape, passed, _⟩
  · subst same
    exact ⟨rfl, distinct⟩
  · exact ⟨shape, passed_rowidsDistinct passed⟩

/-- For every context, keys, policy, clauses, tables, values, rest of the queue and written row: if the
reached rows ({name}`upsertSteps`) of the queue are bounded ({name}`upsertBounded`), and the first row runs
to a next table, then the next table has rowids in range, and the reached rows of the rest of the queue
over it are bounded. Proof sketch: unfold {name}`upsertBounded` for the first step and for the rest; the
first step contributes the test of its next table. -/
theorem upsertBounded_step {context : Resolved.EvalContext} {keys : List UniqueKey} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {current next : Table} {values : List Value}
    {rest : List (List Value)} {written : Option Row}
    (run : upsertRow context keys policy clauses current values = .ok (next, written))
    (bounded : upsertBounded (upsertSteps context keys policy clauses current (values :: rest)) = true) :
    next.RowidsInRange ∧ upsertBounded (upsertSteps context keys policy clauses next rest) = true := by
  simp only [upsertSteps, run, upsertBounded, List.all_cons, Bool.and_eq_true] at bounded ⊢
  exact ⟨(Table.rowidsInRange_iff next).mp bounded.1.2, bounded.2⟩

end LiteralData
end Belay.Sqlite.Model
