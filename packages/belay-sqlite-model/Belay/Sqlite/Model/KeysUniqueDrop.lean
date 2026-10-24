import Belay.Sqlite.Model.DropPositionLaws
import Belay.Sqlite.Model.KeysUniqueFrame
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The theorem of the atom "keys unique" (ADR 0022, D3, slice 2) for DROP TABLE and DROP INDEX
without the row engine. A drop keeps the other objects with their rows and renumbers them
({lit}`keptBelow`). A kept table keeps its keys when no unique index that the drop keeps is on a
table that it drops: otherwise the index would name the next kept position, as the task file's
counterexample shows. -/

namespace Belay.Sqlite.Model

/-- The condition of DROP for the given catalog and positions: for every position of the catalog
that holds a unique index and that the drop keeps, the drop keeps the position of the index's
table too. Positions that hold a table, a trigger or an index that is not unique, and the
positions that the drop removes, require nothing. -/
def Catalog.DropCondition (catalog : Catalog) (positions : List Nat) : Prop :=
  ∀ place object index, catalog[place]? = some object → object.entry = .index index → index.unique = true →
    place ∉ positions → index.table ∉ positions

/-- For every database, positions, position and table: if the database after
{name}`Database.drop` has the table at the position, the database has the same table, with its
entry and rows, at an old position that the drop keeps and that {name}`keptBelow` moves to the
position. A drop keeps its tables whole: {name}`CatalogEntry.afterDrop` changes only an index.
Proof sketch: a table after the drop is a kept table at a lower position
({name}`exists_keptBelow`), with its entry and its rows ({name}`getElem?_keptAfterDrop`). -/
theorem Database.table_drop_cases {database : Database} {positions : List Nat} {position : Nat} {table : Table}
    (present : (database.drop positions).table position = some table) :
    ∃ old, !positions.contains old ∧ keptBelow positions old = position ∧ database.table old = some table := by
  unfold Database.table at present
  obtain ⟨shape, atShape, same⟩ := Option.map_eq_some_iff.mp present
  have inside : position < (keptAfterDrop positions database.catalog).length := by
    cases atPosition : (database.drop positions).catalog[position]? with
    | none => simp [Catalog.tableAt, atPosition] at atShape
    | some object =>
      have below := (List.getElem?_eq_some_iff.mp atPosition).1
      simpa [Database.drop, Catalog.drop_eq_keptAfterDrop] using below
  obtain ⟨old, kept, moved⟩ := exists_keptBelow positions database.catalog inside
  subst moved
  have entry : (database.drop positions).catalog[keptBelow positions old]? =
      (database.catalog[old]?).map fun object => { object with entry := object.entry.afterDrop positions } := by
    simp only [Database.drop, Catalog.drop_eq_keptAfterDrop, List.getElem?_map, getElem?_keptAfterDrop _ _ kept]
  have oldShape : database.catalog.tableAt old = some shape := by
    unfold Catalog.tableAt at atShape ⊢
    rw [entry] at atShape
    cases atOld : database.catalog[old]? with
    | none => simp [atOld] at atShape
    | some object =>
      rcases object with ⟨name, objectEntry⟩
      cases objectEntry <;> simp_all [CatalogEntry.afterDrop]
  have oldRows : (database.drop positions).rows.getD (keptBelow positions old) [] = database.rows.getD old [] := by
    simp only [List.getD_eq_getElem?_getD, Database.drop_rows, getElem?_keptAfterDrop _ _ kept]
  have found : database.table old = some table := by
    rw [← same, oldRows]
    simp [Database.table, oldShape]
  exact ⟨old, kept, rfl, found⟩

/-- For every database and positions: if the database satisfies {name}`Database.KeysUnique` and
its catalog meets the condition of DROP ({name}`Catalog.DropCondition`), the database after
{name}`Database.drop` satisfies {name}`Database.KeysUnique`. Proof sketch: a table after the drop
is a kept table at a lower position ({name}`exists_keptBelow`), with its entry and its rows
({name}`getElem?_keptAfterDrop`); each of its keys is a key of its old position: a unique index
on it is a kept index whose table is kept by the condition, and two kept positions with the same
new position are equal ({name}`keptBelow_injective`). The frame lemma
({name}`Database.KeysUnique.frame`) gives the atom. -/
theorem Database.KeysUnique.drop {database : Database} (unique : database.KeysUnique) {positions : List Nat}
    (condition : database.catalog.DropCondition positions) : (database.drop positions).KeysUnique := by
  intro position table present
  obtain ⟨old, kept, moved, found⟩ := Database.table_drop_cases present
  subst moved
  refine unique.frame found rfl fun key member => ?_
  unfold Catalog.uniqueKeys at member ⊢
  rcases List.mem_append.mp member with own | indexed
  · exact List.mem_append_left _ own
  · apply List.mem_append_right
    obtain ⟨after, inDrop, gives⟩ := List.mem_filterMap.mp indexed
    simp only [Database.drop, Catalog.drop_eq_keptAfterDrop, List.mem_map] at inDrop
    obtain ⟨object, inKept, rfl⟩ := inDrop
    obtain ⟨place, placeKept, atPlace⟩ := mem_keptAfterDrop inKept
    rcases object with ⟨name, objectEntry⟩
    cases objectEntry with
    | table _ => simp [CatalogEntry.afterDrop] at gives
    | trigger _ => simp [CatalogEntry.afterDrop] at gives
    | index index =>
      simp only [CatalogEntry.afterDrop, Bool.and_eq_true, beq_iff_eq] at gives
      split at gives
      · rename_i onTable
        simp only [Option.some.injEq] at gives
        subst gives
        have tableKept := condition place _ index atPlace rfl onTable.2 (by simpa using placeKept)
        have sameTable := keptBelow_injective positions (by simpa using tableKept) kept onTable.1
        exact List.mem_filterMap.mpr ⟨_, List.mem_of_getElem? atPlace, by simp [sameTable, onTable.2]; rfl⟩
      · simp at gives

/-- For every clock value, counters, parameter list, DROP without foreign key rules and trigger programs
({lean}`(none : Option Resolved.WriteRules)`) and database: if the database satisfies
{name}`Database.KeysUnique` and its catalog meets the condition of DROP at the positions
({name}`Catalog.DropCondition`), the effect of {name}`runStatement` satisfies
{name}`Effect.KeysUnique`. Proof sketch: the effect is the database after
{name}`Database.drop` ({name}`Database.KeysUnique.drop`). -/
theorem runStatement_drop_keysUnique (clock : Int) (counters : Counters) (parameters : List Value) (positions : List Nat)
    {database : Database} (unique : database.KeysUnique) (condition : database.catalog.DropCondition positions) :
    (runStatement clock counters parameters (.drop positions none) database).effect.KeysUnique := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys, step]
  exact Effect.keysUnique_of_effectDatabase (unique.drop condition)

end Belay.Sqlite.Model
