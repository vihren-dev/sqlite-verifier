import Belay.Sqlite.Model.ResolveCreateIndexCatalog
import Belay.Sqlite.Model.CatalogValidDrop
import Belay.Sqlite.Model.Resolution.TriggerDefinitions

set_option doc.verso true

/-! CREATE TRIGGER gives a valid catalog (ADR 0022, D3, slice 4): when the resolver of a script
appends a trigger to a valid catalog, the catalog stays valid. The trigger needs a table of the
catalog. SQLite's schema tables are no table of the catalog, but their names are reserved, and the
resolver refuses a trigger on a reserved table name. -/

namespace Belay.Sqlite.Model

/-- For every name and schema table name: if {name}`schemaTableName?` gives a name for the name,
the name is reserved ({name}`reservedName`). Proof sketch: the name is the same name as
one of four names that begin with {lit}`sqlite_`, so its folded name is one of them. -/
theorem schemaTableName_reserved {name schema : Identifier} (found : schemaTableName? name = some schema) :
    reservedName name = true := by
  have prefixed : ∀ other : Identifier, name.sameName other = true →
      (bytes! "sqlite_").isPrefixOf other.folded = true → reservedName name = true := by
    intro other same pre
    simp only [Identifier.sameName, beq_iff_eq] at same
    simp only [reservedName, same, pre]
  unfold schemaTableName? at found
  split at found
  · rename_i h
    simp only [Bool.or_eq_true] at h
    rcases h with h | h <;> exact prefixed _ h (by decide)
  · split at found
    · rename_i h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h <;> exact prefixed _ h (by decide)
    · cases found

/-- For every valid catalog, name and trigger: if
* the name is not reserved;
* the table of the trigger has a name that is not reserved;
* the catalog finds the table of the trigger ({name}`Catalog.findTable`), or
  {name}`schemaTableName?` gives a name for it;

then the catalog with the trigger appended ({name}`Catalog.createTrigger`) is valid. Proof sketch:
the table is found, because a schema table name is reserved ({name}`schemaTableName_reserved`);
the longer catalog finds it too ({name}`Catalog.findTable_append_of_some`), and
{name}`Catalog.Valid.append` ends the proof. -/
theorem Catalog.Valid.createTrigger {limits : Limits} {catalog : Catalog} {name : Identifier}
    {trigger : CatalogTrigger} (valid : catalog.Valid limits) (notReserved : reservedName name = false)
    (tableNotReserved : reservedName trigger.table = false)
    (known : (catalog.findTable trigger.table).isSome = true ∨ (schemaTableName? trigger.table).isSome = true) :
    (catalog.createTrigger name trigger).Valid limits := by
  refine valid.append _ (fun isTrigger => absurd isTrigger (by simp [CatalogObject.isTrigger,
    CatalogEntry.isTrigger])) ?_
  have found : (catalog.findTable trigger.table).isSome = true := by
    rcases known with found | schema
    · exact found
    · obtain ⟨_, schema⟩ := Option.isSome_iff_exists.mp schema
      simp [schemaTableName_reserved schema] at tableNotReserved
  obtain ⟨pair, present⟩ := Option.isSome_iff_exists.mp found
  simp [CatalogObject.supported, notReserved, Catalog.findTable_append_of_some
    [{ name, entry := .trigger trigger }] present]

/-- For every limits, valid catalog and successful resolution of CREATE TRIGGER, the catalog after
the resolution is valid. Proof sketch: split every branch of the resolver. A prepare error and a
statement that does nothing return the catalog. The branch that appends a trigger is
{name}`Catalog.Valid.createTrigger`. -/
theorem resolveCreateTrigger_valid (limits : Limits) (catalog after : Catalog) (name : Identifier)
    (ifNotExists : Bool) (trigger : CatalogTrigger) (statement : Resolved.Statement)
    (valid : catalog.Valid limits)
    (ok : resolveCreateTrigger catalog name ifNotExists trigger = .ok (statement, after)) :
    after.Valid limits := by
  unfold resolveCreateTrigger at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (cases ok; exact valid.drop (Catalog.DropClosed.nil catalog))
    | (cases ok; done)
    | (cases ok
       exact Catalog.Valid.createTrigger valid (by simp_all) (by simp_all) (by simp_all))

end Belay.Sqlite.Model
