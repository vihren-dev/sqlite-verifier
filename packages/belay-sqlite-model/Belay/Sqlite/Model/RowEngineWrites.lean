import Belay.Sqlite.Model.RowEngineUpdate
import Belay.Sqlite.Model.RowEngineInsert
import Belay.Sqlite.Model.ForeignKeyWrites
import Belay.Sqlite.Model.RowCreditHolds

set_option doc.verso true

/-! The row engine keeps a property of databases with the laws of {lit}`WriteLaws` (ADR 0022, D3, slices
2, 3 and 4): {lit}`runRows` keeps the invariant of the row engine at every fuel, and so the writes through
it ({lit}`rowsKeys`, {lit}`dropKeys`) give effects whose databases have the property. -/

namespace Belay.Sqlite.Model

variable {invariant : Database → Prop}

/-- For every invariant with {name}`WriteLaws`, catalog, links and fuel: {name}`runRows` keeps the
invariant of the row engine ({name}`NestedRun.Keeps`). Proof sketch: induction on the fuel;
without fuel the work is undescribed; with fuel, the rows of the work run in a fold of
{name}`deleteRow_holds`, {name}`updateRow_holds` or {name}`insertRow_holds`, whose nested writes
run with one less fuel and keep the invariant by induction. -/
theorem runRows_holds (laws : WriteLaws invariant) (catalog : Catalog) (links : List ForeignKeyLink) :
    ∀ fuel, NestedRun.Keeps invariant catalog (runRows catalog links fuel)
  | 0 => fun _ _ _ _ => trivial
  | fuel + 1 => fun frame work state holds => by
    have nested := NestedRun.credited_keeps (runRows_holds laws catalog links fuel)
    cases work with
    | delete position rowids record ignore fire =>
      simp only [runRows]
      exact ResultHolds.foldlM (fun reached rowid held =>
        deleteRow_holds laws nested frame position record ignore fire held rowid) rowids state holds
    | update position change assigned changed rowids record =>
      simp only [runRows]
      exact ResultHolds.foldlM (fun reached rowid held =>
        updateRow_holds laws nested frame position change assigned changed record held rowid) rowids state holds
    | insert position rows policy clauses multiWrite record =>
      simp only [runRows]
      exact ResultHolds.foldlM (fun reached values held =>
        insertRow_holds laws nested frame position policy clauses multiWrite record held values) rows state holds

/-- For every invariant, input database, target, flag and result of the row engine: if the input
database has the property and the result keeps the invariant over the input catalog (a
success satisfies {name}`KeyState.Holds` and a stop {name}`KeyStop.Holds`), the
database of the effect of {name}`keyRun` ({name}`effectDatabase`) has the property. Proof sketch: that
database is the input database or the database of the reached state. -/
theorem keyRun_holds {input : Database} (every : invariant input) (target : Nat) (plain : Bool)
    {result : Except KeyStop KeyState}
    (holds : ResultHolds (KeyState.Holds invariant input.catalog) (KeyStop.Holds invariant input.catalog) result) :
    invariant (effectDatabase (keyRun input target plain result).effect) := by
  unfold keyRun
  repeat' split
  all_goals first | exact every | (subst_vars; exact holds) | skip
  all_goals simp_all [effectDatabase, ResultHolds, KeyStop.Holds, KeyState.Holds]

/-- For every invariant with {name}`WriteLaws`, rules, clock value, target, work, database, flag and
algorithm: if the database has the property, the database of the effect
of {name}`rowsKeys` has it. Proof sketch: {name}`keyRun_holds` of {name}`runRows_holds` from the
state with the rows of the database ({name}`KeyState.holds_start`). -/
theorem rowsKeys_holds (laws : WriteLaws invariant) (rules : Resolved.WriteRules) (clock : Int) (target : Nat)
    (work : RowWork) {database : Database} (every : invariant database) (plain : Bool)
    (algorithm : Option ConflictAlgorithm) :
    invariant (effectDatabase (rowsKeys rules clock target work database plain algorithm).effect) :=
  keyRun_holds every target plain
    (runRows_holds laws _ _ _ _ work _ (KeyState.holds_start every))

/-- For every invariant with {name}`WriteLaws`, rules, clock value, positions and database: if the
database has the property, and DROP at the positions keeps the property of a database with the
catalog of the database ({lit}`drop`), the database of the effect of
{name}`dropKeys` has it. Proof sketch: the DELETE of the rows is {name}`rowsKeys_holds`; after it
the catalog is the input catalog ({name}`keyRun_ok_catalog`), so the drop keeps the property. -/
theorem dropKeys_holds (laws : WriteLaws invariant) (rules : Resolved.WriteRules) (clock : Int) (positions : List Nat)
    {database : Database} (every : invariant database)
    (drop : ∀ other : Database, other.catalog = database.catalog → invariant other →
      invariant (other.drop positions)) :
    invariant (effectDatabase (dropKeys rules clock positions database).effect) := by
  unfold dropKeys
  split
  · dsimp only
    split
    · rename_i target _ table _ _ after deleted
      have afterEvery := rowsKeys_holds laws rules clock target
        (.delete target (table.scanRows.map (·.rowid)) false true false) every true none
      rw [deleted] at afterEvery
      exact drop after (keyRun_ok_catalog deleted) afterEvery
    · exact rowsKeys_holds laws rules clock _ _ every true none
  · exact drop database rfl every

end Belay.Sqlite.Model
