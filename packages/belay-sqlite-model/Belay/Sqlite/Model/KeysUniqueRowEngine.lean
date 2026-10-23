import Belay.Sqlite.Model.RowEngineWrites
import Belay.Sqlite.Model.KeysUniqueUpsert
import Belay.Sqlite.Model.KeysUniqueDrop

set_option doc.verso true

/-! The row engine keeps the atom "keys unique" (ADR 0022, D3, slice 2, part 2): the atom has the
facts of {lit}`TableFacts`, so {lit}`runRows` and the writes through it keep it
({lit}`RowEngineWrites`). -/

namespace Belay.Sqlite.Model

/-- The fact of a table that {name}`Database.KeysUnique` says of each table: it satisfies
{name}`Table.KeysUnique` for the unique keys of its position ({name}`Catalog.uniqueKeys`). -/
def Table.keysUniqueFact (catalog : Catalog) (position : Nat) (table : Table) : Prop :=
  table.KeysUnique (catalog.uniqueKeys position table.shape)

/-- "Keys unique" has the facts of {name}`TableFacts`. Proof sketch: a sublist with the same entry
keeps the keys unique ({name}`Table.KeysUnique.sublist`); a table that passes
{name}`LiteralData.constraints` has them by {name}`Table.constraints_iff`. -/
theorem keysUniqueFacts : TableFacts Table.keysUniqueFact where
  sublist catalog position table other unique same sub := by
    unfold Table.keysUniqueFact at *
    rw [same]
    exact unique.sublist sub
  constraints catalog position table passed := ((Table.constraints_iff _ table).mp passed).2.2.2

/-- For every rules, clock value, target, work, database, flag and algorithm: if the database
satisfies {name}`Database.KeysUnique`, the database of the effect of {name}`rowsKeys` satisfies
it. Proof sketch: {name}`rowsKeys_holds` for {name}`keysUniqueFacts`. -/
theorem rowsKeys_keysUnique (rules : Resolved.WriteRules) (clock : Int) (target : Nat) (work : RowWork)
    {database : Database} (unique : database.KeysUnique) (plain : Bool) (algorithm : Option ConflictAlgorithm) :
    (effectDatabase (rowsKeys rules clock target work database plain algorithm).effect).KeysUnique :=
  rowsKeys_holds keysUniqueFacts rules clock target work (fact := Table.keysUniqueFact) unique plain algorithm

/-- For every rules, clock value, positions and database: if the database satisfies
{name}`Database.KeysUnique` and its catalog meets the condition of DROP at the positions
({name}`Catalog.DropCondition`), the database of the effect of {name}`dropKeys` satisfies it.
Proof sketch: {name}`dropKeys_holds` for {name}`keysUniqueFacts`, with
{name}`Database.KeysUnique.drop` after the DELETE, whose catalog is the input catalog. -/
theorem dropKeys_keysUnique (rules : Resolved.WriteRules) (clock : Int) (positions : List Nat)
    {database : Database} (unique : database.KeysUnique) (condition : database.catalog.DropCondition positions) :
    (effectDatabase (dropKeys rules clock positions database).effect).KeysUnique :=
  dropKeys_holds keysUniqueFacts rules clock positions (fact := Table.keysUniqueFact) unique
    fun _ same kept => Database.KeysUnique.drop kept (same ▸ condition)

end Belay.Sqlite.Model
