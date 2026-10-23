import Belay.Sqlite.Model.KeysUniqueUpsert
import Belay.Sqlite.Model.RowLocalFrame
import Belay.Sqlite.Model.RowEngineFacts

set_option doc.verso true

/-! The theorem of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3),
stated for every {lit}`RowLocalAtom`, for an INSERT with {lit}`ON CONFLICT` clauses or a conflict
algorithm (upsert) without the row engine. Each row either keeps the table or stores a table that
passed {lit}`LiteralData.checkedRow` and has the catalog entry of the table, so every table that
the rows reach has the atom, also the table before a failed row, which a FAIL failure keeps. It
follows {lit}`KeysUniqueUpsert`. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every keys, algorithms, two tables, proposed row and row: if {name}`insertChecked`
succeeds with a table, that table is the input table, or it has the catalog entry of the input
table and passed {name}`constraints` for the keys. Proof sketch: a blocking key fails or keeps the
table ({name}`failedConstraint_ok`), and otherwise {name}`checkedRow_constraints`; the table with
the rows that REPLACE removed and the proposed row has the entry of the table. -/
theorem insertChecked_constraints {keys : List UniqueKey} {algorithms : List ConflictAlgorithm} {table next : Table}
    {proposed : Row} {written : Option Row} (ok : insertChecked keys algorithms table proposed = .ok (next, written)) :
    next = table ∨ (next.shape = table.shape ∧ constraints keys next = true) := by
  unfold insertChecked at ok
  split at ok
  · exact .inl (failedConstraint_ok ok)
  · obtain ⟨same, passed⟩ := checkedRow_constraints ok
    exact .inr ⟨by rw [same]; rfl, same ▸ passed⟩

/-- For every context, keys, table, assignments, filter, two rows, result table and row: if
{name}`updateExisting` succeeds with a table, that table is the input table, or it has the
catalog entry of the input table and passed {name}`constraints` for the keys. Proof sketch: a
filter that is not true keeps the table, a refused rowid alias fails, and otherwise
{name}`checkedRow_constraints`; the table with a row replaced has the entry of the table. -/
theorem updateExisting_constraints {context : Resolved.EvalContext} {keys : List UniqueKey} {table next : Table}
    {assignments : List (Nat × Resolved.Expr)} {filter : Option Resolved.Expr} {existing proposed : Row}
    {written : Option Row} (ok : updateExisting context keys table assignments filter existing proposed = .ok (next, written)) :
    next = table ∨ (next.shape = table.shape ∧ constraints keys next = true) := by
  unfold updateExisting at ok
  dsimp only at ok
  split at ok
  · simp only [Except.ok.injEq, Prod.mk.injEq] at ok
    exact .inl ok.1.symm
  · split at ok
    · simp at ok
    · obtain ⟨same, passed⟩ := checkedRow_constraints ok
      exact .inr ⟨by rw [same]; rfl, same ▸ passed⟩

/-- For every context, keys, policy, clauses, table and values: if {name}`upsertRow` succeeds with
a table, that table is the input table, or it has the catalog entry of the input table and passed
{name}`constraints` for the keys. Proof sketch: each branch fails, keeps the table
({name}`failedConstraint_ok`, DO NOTHING, a DO UPDATE whose filter is not true), or stores a table
that {name}`checkedRow` passed ({name}`insertChecked_constraints`,
{name}`updateExisting_constraints`). -/
theorem upsertRow_constraints {context : Resolved.EvalContext} {keys : List UniqueKey} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {table next : Table} {values : List Value} {written : Option Row}
    (ok : upsertRow context keys policy clauses table values = .ok (next, written)) :
    next = table ∨ (next.shape = table.shape ∧ constraints keys next = true) := by
  unfold upsertRow at ok
  split at ok
  · simp at ok
  · dsimp only at ok
    split at ok
    · exact .inl (failedConstraint_ok ok)
    · split at ok
      · exact .inl (failedConstraint_ok ok)
      · split at ok
        · exact .inl (failedConstraint_ok ok)
        · split at ok
          · exact insertChecked_constraints ok
          · split at ok
            · simp only [Except.ok.injEq, Prod.mk.injEq] at ok
              exact .inl ok.1.symm
            · exact updateExisting_constraints ok

/-- For every atom, context, keys, policy, clauses, table and rows: if the atom is a
{name}`RowLocalAtom` and the table has it, the table of the result of the rows
({name}`upsertSummary` of {name}`upsertSteps`) has the catalog entry of the table and the atom: the
final table when the rows succeed, and the table before the failed row when a row fails. Proof
sketch: induction on the rows; each row keeps the table or stores one that passed
{name}`constraints` with the same entry ({name}`upsertRow_constraints`), which has the atom
({name}`RowLocalAtom.constraints`). -/
theorem upsertSummary_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (context : Resolved.EvalContext)
    (keys : List UniqueKey) (policy : Resolved.ConflictPolicy) (clauses : List Resolved.ConflictClause) :
    ∀ (rows : List (List Value)) {table : Table}, atom table →
      match upsertSummary table (upsertSteps context keys policy clauses table rows) with
      | .ok (final, _) => final.shape = table.shape ∧ atom final
      | .error (_, reached, _) => reached.shape = table.shape ∧ atom reached
  | [], _, holds => ⟨rfl, holds⟩
  | values :: rest, table, holds => by
    simp only [upsertSteps, upsertSummary]
    cases result : upsertRow context keys policy clauses table values with
    | error reason => exact ⟨rfl, holds⟩
    | ok pair =>
      obtain ⟨next, written⟩ := pair
      have kept : next.shape = table.shape ∧ atom next := by
        rcases upsertRow_constraints result with same | ⟨shape, passed⟩
        · exact ⟨same ▸ rfl, same ▸ holds⟩
        · exact ⟨shape, rowLocal.constraints keys next passed⟩
      have later := upsertSummary_rowLocal rowLocal context keys policy clauses rest kept.2
      dsimp only
      rcases summary : upsertSummary next (upsertSteps context keys policy clauses next rest) with
        ⟨_, _, _⟩ | ⟨_, _⟩ <;> simp only [summary] at later ⊢ <;> exact ⟨later.1.trans kept.1, later.2⟩

end LiteralData

/-- For every atom, clock value, parameter list, INSERT with {lit}`ON CONFLICT` clauses or a
conflict algorithm without foreign key rules and trigger programs
({lean}`(none : Option Resolved.WriteRules)`), and database: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, every table of the database of the
effect of {name}`runStatement` has it, on success and on every error, which is more than
{name}`Effect.Satisfies` asks. It assumes nothing about the support check. Proof sketch: the
statement stores the table of {name}`LiteralData.upsertSummary` at the target, which has the atom
and the entry of the target ({name}`LiteralData.upsertSummary_rowLocal`), with
{name}`Database.EachTable.setRows`. -/
theorem runStatement_upsert_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String))
    (algorithm : Option ConflictAlgorithm) (subqueries : List Resolved.Query) {database : Database}
    (every : database.EachTable atom) :
    (effectDatabase (runStatement clock parameters
      (.upsert target rows clauses returning algorithm subqueries none) database).effect).EachTable atom := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys]
  split
  · exact every
  · rename_i table found
    have summary := LiteralData.upsertSummary_rowLocal rowLocal
      (Resolved.statementContext clock parameters database subqueries)
      (database.keys target table) (database.catalog.writePolicy target table.shape algorithm) clauses
      (Resolved.rowsAt (Resolved.statementContext clock parameters database subqueries) table.shape.columns rows)
      (every target table found)
    dsimp only
    split
    · rename_i final written result
      rw [result] at summary
      obtain ⟨shape, holds⟩ := summary
      cases final
      subst shape
      exact every.setRows found holds
    · rename_i reason reached written result
      rw [result] at summary
      obtain ⟨shape, holds⟩ := summary
      cases reached
      subst shape
      exact every.setRows found holds

end Belay.Sqlite.Model
