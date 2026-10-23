import Belay.Sqlite.Model.Database

set_option doc.verso true

/-! The tables that a check pragma walks (ADR 0019, D2): the catalog positions that it checks,
and the items, such as rows or failures, of each table that gives items. Without a table name,
SQLite walks the tables in the order of its schema hash table, which the model does not
describe, so a pragma gives an exact output only when at most one table gives items. -/

namespace Belay.Sqlite.Model

/-- The catalog positions that a check pragma checks: the position {lit}`table`, or every
position with {lean}`(none : Option Nat)`. -/
def Database.checkPositions (database : Database) : Option Nat → List Nat
  | some position => [position]
  | none => List.range database.catalog.length

/-- The items of each table at the positions that gives items ({lit}`items`), in the order of
the positions. A position without a table gives none. -/
def Database.blocks {α : Type} (database : Database) (positions : List Nat) (items : Nat → Table → List α) :
    List (List α) :=
  positions.filterMap fun position => (database.table position).bind fun table =>
    match items position table with
    | [] => none
    | found => some found

/-- For every database, positions and items: no table at the positions gives items
({name}`Database.blocks` is empty) exactly when every table at the positions gives no items.
Proof sketch: a {lit}`filterMap` is empty when each position gives none, and a table gives none
exactly when it has no items. -/
theorem Database.blocks_eq_nil {α : Type} (database : Database) (positions : List Nat) (items : Nat → Table → List α) :
    database.blocks positions items = [] ↔
      ∀ position ∈ positions, ∀ table, database.table position = some table → items position table = [] := by
  unfold Database.blocks
  rw [List.filterMap_eq_nil_iff]
  refine forall_congr' fun position => imp_congr_right fun _ => ?_
  cases database.table position with
  | none => simp
  | some table =>
    simp only [Option.bind_some, forall_eq', Option.some.injEq]
    split <;> simp_all

/-- For every database, positions and items: each block of {name}`Database.blocks` has an item.
Proof sketch: a table that gives no items gives no block. -/
theorem Database.blocks_ne_nil {α : Type} {database : Database} {positions : List Nat} {items : Nat → Table → List α}
    {block : List α} (member : block ∈ database.blocks positions items) : block ≠ [] := by
  unfold Database.blocks at member
  obtain ⟨position, _, made⟩ := List.mem_filterMap.mp member
  cases present : database.table position with
  | none => simp [present] at made
  | some table =>
    simp only [present, Option.bind_some] at made
    revert made
    cases items position table with
    | nil => simp
    | cons item rest =>
      intro made
      cases made
      simp

end Belay.Sqlite.Model
