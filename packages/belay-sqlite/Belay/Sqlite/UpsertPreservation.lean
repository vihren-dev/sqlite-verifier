import Belay.Sqlite.WritePreservation
import Belay.Sqlite.UpsertRun

set_option doc.verso true

/-! Preservation of {lit}`Conforms` by INSERT with {lit}`ON CONFLICT` clauses (ADR 0012,
amendment 4, slice 5c): every row of an UPSERT keeps the table's shape and
{lit}`Table.Valid`. A skipped row keeps the table; an inserted row is
{lit}`Table.RowsValid.insertRow`; an updated row replaces one row with a row of the same
conditions; a row of REPLACE deletes rows and appends one row. The distinct rowids come
from the check of {lit}`LiteralData.checkedRow`. -/

namespace Belay.Sqlite

/-- For every table, old row and new row: assume {name}`Table.RowsValid` and that the new
row has a valid rowid, one cell per column, {name}`Row.Stored` cells and
{name}`Row.Aliased`. Then {name}`LiteralData.replaceRow` keeps {name}`Table.RowsValid`.
Proof sketch: each row of the result is the new row or an old row. -/
theorem Table.RowsValid.replaceRow {table : Table} {old new : Row} (valid : table.RowsValid)
    (rowid : validRowid new.rowid) (width : new.values.length = table.shape.columns.length)
    (stored : new.Stored table.shape.columns) (aliased : new.Aliased table.shape.rowidAlias) :
    (LiteralData.replaceRow table old new).RowsValid := by
  intro row member
  simp only [LiteralData.replaceRow, List.mem_map] at member
  obtain ⟨other, otherMember, equal⟩ := member
  subst equal
  split
  · exact ⟨rowid, width, stored, aliased⟩
  · exact valid other otherMember

/-- For every key list, clause list, table, proposed row and result: if
{name}`LiteralData.handlingClause` gives a clause and a row, the row is a row of the
table. Proof sketch: the row is a result of {lit}`List.find?` over the table's rows. -/
theorem LiteralData.handlingClause_mem {keys : List (List Nat)} {clauses : List Resolved.ConflictClause}
    {table : Table} {proposed existing : Row} {clause : Resolved.ConflictClause}
    (found : handlingClause keys clauses table proposed = some (clause, existing)) : existing ∈ table.rows := by
  obtain ⟨other, _, image⟩ := List.exists_of_findSome?_eq_some found
  cases row : conflictingRow (clauseKeys keys other) table proposed with
  | none => simp [row] at image
  | some row' =>
    simp only [row, Option.map_some, Option.some.injEq, Prod.mk.injEq] at image
    obtain ⟨_, rfl⟩ := image
    exact List.mem_of_find?_eq_some row

/-- For every valid table and {lit}`DO UPDATE` of a row of the table: assume that every
row of the result has a bounded rowid. If {name}`LiteralData.updateExisting` succeeds,
its table has the same shape and is {name}`Table.Valid`. Proof sketch: a false filter keeps the table; otherwise the changed
row is {name}`LiteralData.assignFrom` of a valid row, its alias cell is an integer (no
{name}`LiteralData.aliasCellMismatch`), and {name}`Table.RowsValid.replaceRow` applies. -/
theorem LiteralData.updateExisting_valid {keys : List (List Nat)} {table next : Table}
    {assignments : List (Nat × Resolved.Expr)} {filter : Option Resolved.Expr} {existing proposed : Row}
    {written : Option Row} (valid : table.Valid) (member : existing ∈ table.rows)
    (bounded : next.rows.all (fun row => boundedInteger row.rowid) = true)
    (step : updateExisting keys table assignments filter existing proposed = .ok (next, written)) :
    next.shape = table.shape ∧ next.Valid := by
  unfold updateExisting at step
  dsimp only at step
  split at step
  · cases step; exact ⟨rfl, valid⟩
  split at step
  · cases step
  rename_i fits
  unfold checkedRow at step
  split at step
  · rename_i passed
    cases step
    have distinct := of_decide_eq_true ((Bool.and_eq_true _ _).mp passed).2
    refine ⟨rfl, distinct, ?_⟩
    obtain ⟨_, width, stored, _⟩ := valid.2 existing member
    let context := existing.values ++ proposed.values
    obtain ⟨_, sameLength, newStored⟩ := assignFrom_valid table.shape.columns assignments context existing stored
    have changedMember : movedRowid table.shape.rowidAlias (assignFrom table.shape.columns assignments context existing)
        ∈ (replaceRow table existing (movedRowid table.shape.rowidAlias
          (assignFrom table.shape.columns assignments context existing))).rows := by
      simp only [replaceRow, List.mem_map]
      exact ⟨existing, member, by simp⟩
    have rowBounded := List.all_eq_true.mp bounded _ changedMember
    refine valid.2.replaceRow (by simpa [boundedInteger, validRowid] using rowBounded) ?_ ?_ ?_
    · rw [movedRowid_values, sameLength, width]
    · intro position column value columnAt cellAt
      rw [movedRowid_values] at cellAt
      exact newStored position column value columnAt cellAt
    · intro position alias
      rw [alias]
      have cellIntegral : ∃ value, (assignFrom table.shape.columns assignments context existing).values[position]? =
          some (.integer value) := by
        simp only [aliasCellMismatch, alias, movedRowid_values] at fits
        revert fits
        cases (assignFrom table.shape.columns assignments context existing).values[position]? with
        | none => simp
        | some value => cases value <;> simp
      obtain ⟨value, cell⟩ := cellIntegral
      exact Row.Aliased.movedRowid cell position rfl
  · cases step

/-- For every table, algorithm and result: if {name}`LiteralData.failedConstraint`
succeeds, its table is the input table. Proof sketch: only IGNORE succeeds, and it
keeps the table. -/
theorem LiteralData.failedConstraint_ok {table next : Table} {algorithm : ConflictAlgorithm}
    {written : Option Row} (step : failedConstraint table algorithm = .ok (next, written)) : next = table := by
  cases algorithm <;> simp only [failedConstraint, failureError, reduceCtorEq] at step
  cases step
  rfl

/-- For every valid table, keys, algorithms and proposed row: assume that the proposed
row has a valid rowid, one cell per column, {name}`Row.Stored` cells and
{name}`Row.Aliased`. If {name}`LiteralData.insertChecked` succeeds, its table has the same
shape and is {name}`Table.Valid`. Proof sketch: a skipped row keeps the table; otherwise
the rows are a sublist of the table's rows followed by the proposed row, and the check
gives distinct rowids. -/
theorem LiteralData.insertChecked_valid {keys : List (List Nat)} {algorithms : List ConflictAlgorithm}
    {table next : Table} {proposed : Row} {written : Option Row} (valid : table.Valid)
    (row : validRowid proposed.rowid ∧ proposed.values.length = table.shape.columns.length ∧
      proposed.Stored table.shape.columns ∧ proposed.Aliased table.shape.rowidAlias)
    (step : insertChecked keys algorithms table proposed = .ok (next, written)) :
    next.shape = table.shape ∧ next.Valid := by
  unfold insertChecked at step
  split at step
  · obtain rfl := failedConstraint_ok step
    exact ⟨rfl, valid⟩
  · dsimp only at step
    unfold checkedRow at step
    split at step
    · rename_i passed
      cases step
      refine ⟨rfl, of_decide_eq_true ((Bool.and_eq_true _ _).mp passed).2, ?_⟩
      intro other member
      simp only [replaced, List.mem_append, List.mem_filter, List.mem_singleton] at member
      rcases member with ⟨old, _⟩ | rfl
      · exact valid.2 other old
      · exact row
    · cases step

end Belay.Sqlite
