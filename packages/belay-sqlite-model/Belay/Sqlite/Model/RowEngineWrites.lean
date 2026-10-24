import Belay.Sqlite.Model.RowEngineUpdate
import Belay.Sqlite.Model.RowEngineInsert
import Belay.Sqlite.Model.ForeignKeyWrites
import Belay.Sqlite.Model.RowCreditHolds

set_option doc.verso true

/-! The row engine keeps an atom with the facts of {lit}`TableFacts` (ADR 0022, D3, slices 2 and
3): {lit}`runRows` keeps the invariant of the row engine at every fuel, and so the writes through
it ({lit}`insertKeys`, {lit}`updateKeys`, {lit}`deleteKeys`, {lit}`dropKeys`) give effects whose
databases have the fact in every table. -/

namespace Belay.Sqlite.Model

variable {fact : Catalog → Nat → Table → Prop}

/-- For every fact with {name}`TableFacts`, catalog, links and fuel: {name}`runRows` keeps the
invariant of the row engine ({name}`NestedRun.Keeps`). Proof sketch: induction on the fuel;
without fuel the work is undescribed; with fuel, the rows of the work run in a fold of
{name}`deleteRow_holds`, {name}`updateRow_holds` or {name}`insertRow_holds`, whose nested writes
run with one less fuel and keep the invariant by induction. -/
theorem runRows_holds (facts : TableFacts fact) (catalog : Catalog) (links : List ForeignKeyLink) :
    ∀ fuel, NestedRun.Keeps fact catalog (runRows catalog links fuel)
  | 0 => fun _ _ _ _ => trivial
  | fuel + 1 => fun frame work state holds => by
    have nested := NestedRun.credited_keeps (runRows_holds facts catalog links fuel)
    cases work with
    | delete position rowids record ignore fire =>
      simp only [runRows]
      exact ResultHolds.foldlM (fun reached rowid held =>
        deleteRow_holds facts nested frame position record ignore fire held rowid) rowids state holds
    | update position change assigned changed rowids record =>
      simp only [runRows]
      exact ResultHolds.foldlM (fun reached rowid held =>
        updateRow_holds facts nested frame position change assigned changed record held rowid) rowids state holds
    | insert position rows policy clauses multiWrite record =>
      simp only [runRows]
      exact ResultHolds.foldlM (fun reached values held =>
        insertRow_holds facts nested frame position policy clauses multiWrite record held values) rows state holds

/-- For every fact, input database, target, flag and result of the row engine: if every table of
the input database has the fact and the result keeps the invariant over the input catalog (a
success satisfies {name}`KeyState.Holds` and a stop {name}`KeyStop.Holds`), every table of the
database of the effect of {name}`keyRun` ({name}`effectDatabase`) has the fact. Proof sketch: that
database is the input database or the database of the reached state. -/
theorem keyRun_holds {input : Database} (every : input.Every fact) (target : Nat) (plain : Bool)
    {result : Except KeyStop KeyState}
    (holds : ResultHolds (KeyState.Holds fact input.catalog) (KeyStop.Holds fact input.catalog) result) :
    (effectDatabase (keyRun input target plain result).effect).Every fact := by
  unfold keyRun
  repeat' split
  all_goals first | exact every | (subst_vars; exact holds) | skip
  all_goals simp_all [effectDatabase, ResultHolds, KeyStop.Holds, KeyState.Holds]

/-- For every fact with {name}`TableFacts`, rules, clock value, target, work, database, flag and
algorithm: if every table of the database has the fact, every table of the database of the effect
of {name}`rowsKeys` has it. Proof sketch: {name}`keyRun_holds` of {name}`runRows_holds` from the
state with the rows of the database ({name}`KeyState.holds_start`). -/
theorem rowsKeys_holds (facts : TableFacts fact) (rules : Resolved.WriteRules) (clock : Int) (target : Nat)
    (work : RowWork) {database : Database} (every : database.Every fact) (plain : Bool)
    (algorithm : Option ConflictAlgorithm) :
    (effectDatabase (rowsKeys rules clock target work database plain algorithm).effect).Every fact :=
  keyRun_holds every target plain
    (runRows_holds facts _ _ _ _ work _ (KeyState.holds_start every))

/-- For every fact with {name}`TableFacts`, rules, clock value, positions and database: if every
table of the database has the fact, and DROP at the positions keeps the fact of a database with the
catalog of the database ({lit}`drop`), every table of the database of the effect of
{name}`dropKeys` has it. Proof sketch: the DELETE of the rows is {name}`rowsKeys_holds`; after it
the catalog is the input catalog ({name}`keyRun_ok_catalog`), so the drop keeps the fact. -/
theorem dropKeys_holds (facts : TableFacts fact) (rules : Resolved.WriteRules) (clock : Int) (positions : List Nat)
    {database : Database} (every : database.Every fact)
    (drop : ∀ other : Database, other.catalog = database.catalog → other.Every fact →
      (other.drop positions).Every fact) :
    (effectDatabase (dropKeys rules clock positions database).effect).Every fact := by
  unfold dropKeys
  split
  · dsimp only
    split
    · rename_i target _ table _ _ after deleted
      have afterEvery := rowsKeys_holds facts rules clock target
        (.delete target (table.scanRows.map (·.rowid)) false true false) every true none
      rw [deleted] at afterEvery
      exact drop after (keyRun_ok_catalog deleted) afterEvery
    · exact rowsKeys_holds facts rules clock _ _ every true none
  · exact drop database rfl every

end Belay.Sqlite.Model
