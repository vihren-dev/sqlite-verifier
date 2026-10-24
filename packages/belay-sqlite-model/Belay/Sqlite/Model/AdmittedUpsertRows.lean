import Belay.Sqlite.Model.AdmittedUpdateRows
import Belay.Sqlite.Model.KeysUniqueUpsert
import Belay.Sqlite.Model.RowEngineFacts

set_option doc.verso true

/-! Where the rows of an upsert come from (ADR 0022, D3, slice 4). A row of an INSERT with
{lit}`ON CONFLICT` clauses or conflict algorithms ({lit}`LiteralData.upsertRow`) keeps the table, or it
stores a table that passed {lit}`LiteralData.checkedRow`. That table has the entry of the table, and
each of its rows is a row of the table, the proposed row, or the changed row of a {lit}`DO UPDATE`.
{lit}`LiteralData.UpsertOrigin` names these three cases, so the proofs of the table atoms read the
cells of a row from its origin. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- The row comes from the table, the proposed row or a {lit}`DO UPDATE` of an upsert: for the
given context, clauses, table, proposed row and row, at least one of these holds:
* the row is a row of the table;
* the row is the proposed row;
* the row is the changed row of a {lit}`DO UPDATE`: there is a row of the table, and a clause of
  the clauses with the assignments of an update action, such that the row is {name}`movedRowid` of
  {name}`assignFrom` of the assignments over the existing row followed by the proposed row, and the
  row has no refused rowid alias cell ({name}`aliasCellMismatch`). -/
def UpsertOrigin (context : Resolved.EvalContext) (clauses : List Resolved.ConflictClause) (table : Table)
    (proposed row : Row) : Prop :=
  row ∈ table.rows ∨ row = proposed ∨
    ∃ existing ∈ table.rows, ∃ assignments, (∃ clause ∈ clauses, ∃ filter, clause.action = .update assignments filter) ∧
      row = movedRowid table.shape.rowidAlias (assignFrom context table.shape.columns assignments
        (existing.values ++ proposed.values) existing) ∧ aliasCellMismatch table.shape.rowidAlias row = false

/-- For every keys, clauses, table, proposed row, clause and existing row: if
{name}`handlingClause` gives the clause with the row, the clause is one of the clauses and the row
is a row of the table. Proof sketch: the clause comes from {lit}`List.findSome?` of the clauses, and
the row from {lit}`List.find?` of the rows. -/
theorem handlingClause_mem {keys : List UniqueKey} {clauses : List Resolved.ConflictClause} {table : Table}
    {proposed existing : Row} {clause : Resolved.ConflictClause}
    (found : handlingClause keys clauses table proposed = some (clause, existing)) :
    clause ∈ clauses ∧ existing ∈ table.rows := by
  unfold handlingClause at found
  obtain ⟨before, chosen, after, split, mapped, _⟩ := List.findSome?_eq_some_iff.mp found
  obtain ⟨row, conflicting, same⟩ := Option.map_eq_some_iff.mp mapped
  simp only [Prod.mk.injEq] at same
  obtain ⟨rfl, rfl⟩ := same
  refine ⟨by rw [split]; simp, ?_⟩
  unfold conflictingRow at conflicting
  exact List.mem_of_find?_eq_some conflicting

/-- For every keys, algorithms, tables, proposed row and written row: if {name}`insertChecked`
succeeds with a table, that table is the input table, or it has the entry of the input table,
passed {name}`constraints` and {name}`rowidsDistinct`, and each of its rows is a row of the input
table or the proposed row. Proof sketch: a blocking key fails or keeps the table
({name}`failedConstraint_ok`); otherwise the table is the one that {name}`checkedRow` passed, the
rows without those that REPLACE removed, and the proposed row. -/
theorem insertChecked_cases {keys : List UniqueKey} {algorithms : List ConflictAlgorithm} {table next : Table}
    {proposed : Row} {written : Option Row} (ok : insertChecked keys algorithms table proposed = .ok (next, written)) :
    next = table ∨ (next.shape = table.shape ∧ (constraints keys next && rowidsDistinct next) = true ∧
      ∀ row ∈ next.rows, row ∈ table.rows ∨ row = proposed) := by
  unfold insertChecked at ok
  split at ok
  · exact .inl (failedConstraint_ok ok)
  · obtain ⟨same, passed⟩ := checkedRow_passed ok
    refine .inr ⟨by rw [same]; rfl, same ▸ passed, fun row member => ?_⟩
    rw [same] at member
    rcases List.mem_append.mp member with kept | added
    · exact .inl (List.mem_filter.mp kept).1
    · exact .inr (List.mem_singleton.mp added)

/-- For every context, keys, table, assignments, filter, existing row, proposed row and written row:
if {name}`updateExisting` succeeds with a table, that table is the input table, or it has the entry
of the input table, passed {name}`constraints` and {name}`rowidsDistinct`, and each of its rows is a
row of the input table or the changed row (the {name}`movedRowid` of the {name}`assignFrom` over the
existing row followed by the proposed row) without a refused rowid alias cell. Proof sketch: a
filter that is not true keeps the table, a refused alias fails, and otherwise the table is the one
that {name}`checkedRow` passed, with one row replaced by the changed row. -/
theorem updateExisting_cases {context : Resolved.EvalContext} {keys : List UniqueKey} {table next : Table}
    {assignments : List (Nat × Resolved.Expr)} {filter : Option Resolved.Expr} {existing proposed : Row}
    {written : Option Row} (ok : updateExisting context keys table assignments filter existing proposed = .ok (next, written)) :
    next = table ∨ (next.shape = table.shape ∧ (constraints keys next && rowidsDistinct next) = true ∧
      ∀ row ∈ next.rows, row ∈ table.rows ∨
        (row = movedRowid table.shape.rowidAlias (assignFrom context table.shape.columns assignments
          (existing.values ++ proposed.values) existing) ∧ aliasCellMismatch table.shape.rowidAlias row = false)) := by
  unfold updateExisting at ok
  dsimp only at ok
  split at ok
  · simp only [Except.ok.injEq, Prod.mk.injEq] at ok
    exact .inl ok.1.symm
  · split at ok
    · simp at ok
    · rename_i _ clear
      obtain ⟨same, passed⟩ := checkedRow_passed ok
      refine .inr ⟨by rw [same]; rfl, same ▸ passed, fun row member => ?_⟩
      rw [same] at member
      obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
      by_cases hit : (old.rowid == existing.rowid) = true
      · exact .inr ⟨by simp [hit], by simpa [hit] using clear⟩
      · exact .inl (by simpa [hit] using oldMember)

/-- For every context, keys, policy, clauses, table, values and written row: if {name}`upsertRow`
succeeds with a table, that table is the input table, or it has the entry of the input table,
passed {name}`constraints` and {name}`rowidsDistinct`, and each of its rows comes from the table, the
proposed row or a {lit}`DO UPDATE` ({name}`UpsertOrigin`). Proof sketch: each branch fails, keeps the
table ({name}`failedConstraint_ok`, DO NOTHING), or stores a table of {name}`insertChecked_cases` or
{name}`updateExisting_cases`; the row and the clause of a {lit}`DO UPDATE` come from
{name}`handlingClause_mem`. -/
theorem upsertRow_cases {context : Resolved.EvalContext} {keys : List UniqueKey} {policy : Resolved.ConflictPolicy}
    {clauses : List Resolved.ConflictClause} {table next : Table} {values : List Value} {written : Option Row}
    (ok : upsertRow context keys policy clauses table values = .ok (next, written)) :
    next = table ∨ (next.shape = table.shape ∧ (constraints keys next && rowidsDistinct next) = true ∧
      ∀ row ∈ next.rows, UpsertOrigin context clauses table (proposedRow table values) row) := by
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
          · rcases insertChecked_cases ok with same | ⟨shape, passed, rows⟩
            · exact .inl same
            · exact .inr ⟨shape, passed, fun row member => (rows row member).imp id .inl⟩
          · rename_i clause existing found
            split at ok
            · simp only [Except.ok.injEq, Prod.mk.injEq] at ok
              exact .inl ok.1.symm
            · rename_i assignments filter action
              obtain ⟨inClauses, inRows⟩ := handlingClause_mem found
              rcases updateExisting_cases ok with same | ⟨shape, passed, rows⟩
              · exact .inl same
              · refine .inr ⟨shape, passed, fun row member => ?_⟩
                rcases rows row member with old | ⟨moved, aliased⟩
                · exact .inl old
                · exact .inr (.inr ⟨existing, inRows, assignments, ⟨clause, inClauses, filter, action⟩, moved, aliased⟩)

/-- For every alias and row: if {name}`movedRowid` of the row has no refused alias cell
({name}`aliasCellMismatch`), it is aliased. This is the case of the changed row of a
{lit}`DO UPDATE`. Proof sketch: without an alias nothing is required; with one, the cell is an
integer, and {name}`movedRowid_aliased` gives the rowid. -/
theorem movedRowid_aliased_of_accepted (alias : Option Nat) (base : Row)
    (accepted : aliasCellMismatch alias (movedRowid alias base) = false) :
    (movedRowid alias base).Aliased alias := by
  rcases alias with _ | position
  · intro position same; cases same
  · have values := movedRowid_values (some position) base
    cases h : base.values[position]? with
    | none => simp [aliasCellMismatch, values, h] at accepted
    | some value =>
      cases value with
      | integer rowid => exact movedRowid_aliased rfl h
      | null => simp [aliasCellMismatch, values, h] at accepted
      | real _ => simp [aliasCellMismatch, values, h] at accepted
      | text _ => simp [aliasCellMismatch, values, h] at accepted
      | blob _ => simp [aliasCellMismatch, values, h] at accepted

end LiteralData
end Belay.Sqlite.Model
