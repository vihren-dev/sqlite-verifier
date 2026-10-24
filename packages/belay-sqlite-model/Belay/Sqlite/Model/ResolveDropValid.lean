import Belay.Sqlite.Model.ResolveDropCatalog

set_option doc.verso true

/-! DROP gives a valid catalog (ADR 0022, D3, slice 4): when the resolver of a script drops the
objects of a valid catalog, the catalog stays valid. DROP TABLE drops the positions of
{lit}`Catalog.tableObjects`, and DROP INDEX and DROP TRIGGER drop one position that holds no table. -/

namespace Belay.Sqlite.Model

/-- For every catalog, name and position: if {name}`Catalog.findIndex` gives the position, the object
of the catalog at the position is an index. Proof sketch: the result comes from {name}`Catalog.find`, and
{name}`findPosition_eq_some_iff` gives the object at the position. -/
theorem Catalog.findIndex_some {catalog : Catalog} {name : Identifier} {position : Nat}
    (found : catalog.findIndex name = some position) :
    ∃ object index, catalog[position]? = some object ∧ object.entry = .index index := by
  unfold Catalog.findIndex at found
  split at found <;> try contradiction
  rename_i place object index hfind
  cases found
  obtain ⟨atPlace, _, _⟩ := (findPosition_eq_some_iff _ _ _ _).mp hfind
  exact ⟨_, index, atPlace, rfl⟩

/-- For every catalog, name, position and trigger that {name}`Catalog.findTrigger` finds: the object of the
catalog at the position is that trigger. Proof sketch: the search finds a numbered object that passes
the test, and a numbered object has the object at its number. -/
theorem Catalog.findTrigger_some {catalog : Catalog} {name : Identifier} {position : Nat}
    {trigger : CatalogTrigger} (found : catalog.findTrigger name = some (position, trigger)) :
    ∃ object, catalog[position]? = some object ∧ object.entry = .trigger trigger := by
  unfold Catalog.findTrigger at found
  obtain ⟨⟨object, place⟩, inside, passes⟩ := List.exists_of_findSome?_eq_some found
  have located := List.mem_zipIdx_iff_getElem?.mp inside
  simp only at located passes
  cases entry : object.entry with
  | table _ => simp [entry] at passes
  | index _ => simp [entry] at passes
  | trigger found =>
    simp only [entry] at passes
    split at passes <;> try contradiction
    simp only [Option.some.injEq, Prod.mk.injEq] at passes
    obtain ⟨rfl, rfl⟩ := passes
    exact ⟨object, located, entry⟩

/-- For every valid catalog and successful resolution of DROP TABLE, the catalog after the resolution is
valid. Proof sketch: a prepare error and a DROP of nothing return the catalog (a drop of no position
meets {name}`Catalog.DropClosed.nil`). The drop of a table meets {name}`Catalog.DropClosed.table`. -/
theorem resolveDropTable_valid (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifExists : Bool) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropTable catalog name ifExists = .ok (statement, after)) : after.Valid limits := by
  unfold resolveDropTable at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (cases ok; exact valid.drop (Catalog.DropClosed.nil catalog))
    | (cases ok; exact valid.drop (Catalog.DropClosed.table valid (by assumption)))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP INDEX, the catalog after the resolution is
valid. Proof sketch: a prepare error returns the catalog, and a DROP of nothing meets
{name}`Catalog.DropClosed.nil`. The drop of an index meets {name}`Catalog.DropClosed.single`, because the
object at the position is an index ({name}`Catalog.findIndex_some`). -/
theorem resolveDropIndex_valid (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifExists : Bool) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropIndex catalog name ifExists = .ok (statement, after)) : after.Valid limits := by
  unfold resolveDropIndex at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (cases ok; exact valid.drop (Catalog.DropClosed.nil catalog))
    | (cases ok
       obtain ⟨object, index, atPosition, entry⟩ := Catalog.findIndex_some (by assumption)
       exact valid.drop (Catalog.DropClosed.single valid atPosition (by simp [entry])))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP TRIGGER, the catalog after the resolution is
valid. Proof sketch: a prepare error returns the catalog, and a DROP of nothing meets
{name}`Catalog.DropClosed.nil`. The drop of a trigger meets {name}`Catalog.DropClosed.single`, because the
object at the position is a trigger ({name}`Catalog.findTrigger_some`). -/
theorem resolveDropTrigger_valid (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifExists : Bool) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropTrigger catalog name ifExists = .ok (statement, after)) : after.Valid limits := by
  unfold resolveDropTrigger at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (cases ok; exact valid.drop (Catalog.DropClosed.nil catalog))
    | (cases ok
       obtain ⟨object, atPosition, entry⟩ := Catalog.findTrigger_some (by assumption)
       exact valid.drop (Catalog.DropClosed.single valid atPosition (by simp [entry])))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP TABLE to a drop of positions, the positions
meet {name}`Catalog.DropClosed`: the drop keeps the table of every index and trigger that it keeps. From it
{name}`Catalog.DropClosed.dropCondition` gives {name}`Catalog.DropCondition`. Proof sketch: split every
branch of the resolver. A prepare error is no drop, a DROP of nothing meets
{name}`Catalog.DropClosed.nil`, and the drop of a table meets {name}`Catalog.DropClosed.table`. -/
theorem resolveDropTable_closed (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifExists : Bool) (positions : List Nat) (valid : catalog.Valid limits)
    (ok : resolveDropTable catalog name ifExists = .ok (.drop positions, after)) : catalog.DropClosed positions := by
  unfold resolveDropTable at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact Catalog.DropClosed.nil catalog)
    | (cases ok; exact Catalog.DropClosed.table valid (by assumption))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP INDEX to a drop of positions, the positions
meet {name}`Catalog.DropClosed`. Proof sketch: as for {name}`resolveDropTable_closed`; the drop of an index
meets {name}`Catalog.DropClosed.single`. -/
theorem resolveDropIndex_closed (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifExists : Bool) (positions : List Nat) (valid : catalog.Valid limits)
    (ok : resolveDropIndex catalog name ifExists = .ok (.drop positions, after)) : catalog.DropClosed positions := by
  unfold resolveDropIndex at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact Catalog.DropClosed.nil catalog)
    | (cases ok
       obtain ⟨object, index, atPosition, entry⟩ := Catalog.findIndex_some (by assumption)
       exact Catalog.DropClosed.single valid atPosition (by simp [entry]))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP TRIGGER to a drop of positions, the positions
meet {name}`Catalog.DropClosed`. Proof sketch: as for {name}`resolveDropTable_closed`; the drop of a trigger
meets {name}`Catalog.DropClosed.single`. -/
theorem resolveDropTrigger_closed (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifExists : Bool) (positions : List Nat) (valid : catalog.Valid limits)
    (ok : resolveDropTrigger catalog name ifExists = .ok (.drop positions, after)) : catalog.DropClosed positions := by
  unfold resolveDropTrigger at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact Catalog.DropClosed.nil catalog)
    | (cases ok
       obtain ⟨object, atPosition, entry⟩ := Catalog.findTrigger_some (by assumption)
       exact Catalog.DropClosed.single valid atPosition (by simp [entry]))
    | (cases ok; done)

end Belay.Sqlite.Model
