import Belay.Sqlite.Model.RowEngineDelete

set_option doc.verso true

/-! The update of a row keeps the invariant of the row engine for an atom
(ADR 0022, D3, slices 2 and 3): {lit}`checkedUpdate` checks the constraints of the table with the
old row replaced, over the state that the {lit}`BEFORE UPDATE` programs left, and the update
writes that table, as the foreign-key steps between them keep the rows. -/

namespace Belay.Sqlite.Model

variable {fact : Catalog → Nat → Table → Prop}

/-- For every fact with {name}`TableFacts`, catalog, state, position, two rows and table: if
{name}`checkedUpdate` passes and the database of the state has the table at the position, the
table with the old row replaced by the new row ({name}`LiteralData.replaceRow`) has the fact for
the position. Proof sketch: the check is {name}`LiteralData.checkedRow` of that table, which
passed {name}`LiteralData.constraints` ({name}`LiteralData.checkedRow_constraints`); the
replaced table has the entry of the table. -/
theorem checkedUpdate_ok (facts : TableFacts fact) {catalog : Catalog} {state : KeyState} {position : Nat} {old new : Row} {table : Table}
    (ok : checkedUpdate catalog state position old new = .ok ()) (found : (state.database catalog).table position = some table) :
    fact catalog position (LiteralData.replaceRow table old new) := by
  unfold checkedUpdate at ok
  rw [found] at ok
  dsimp only at ok
  split at ok
  · cases ok
  · split at ok
    · rename_i reached passed
      obtain ⟨stored, written⟩ := reached
      exact facts.constraints catalog position _ (LiteralData.checkedRow_constraints passed).2
    · cases ok

/-- For every fact, catalog, state, position, two rows and stop: if {name}`checkedUpdate` fails with
the stop, the stop satisfies {name}`KeyStop.Holds`: it carries no state. Proof sketch: each
failure is an error of the statement or undescribed. -/
theorem checkedUpdate_error {catalog : Catalog} {state : KeyState} {position : Nat} {old new : Row} {stop : KeyStop}
    (failed : checkedUpdate catalog state position old new = .error stop) : stop.Holds fact catalog := by
  unfold checkedUpdate at failed
  repeat' (first | split at failed | dsimp only at failed)
  all_goals first | (cases failed; trivial) | cases failed

/-- For every fact with {name}`TableFacts`, catalog, three states, position, two rows and rowid: if the first state satisfies
{name}`KeyState.Holds`, {name}`checkedUpdate` passes over it, the second and the third state
have its rows, and the old row has the rowid, then the third state with the row of the rowid
replaced by the new row ({name}`KeyState.changeRows`) satisfies {name}`KeyState.Holds`.
This is the write of {name}`updateRow`. Proof sketch: the written table is the table that
{name}`checkedUpdate_ok` checked. -/
theorem updateWrite_holds (facts : TableFacts fact) {catalog : Catalog} {state before other : KeyState} {position : Nat} {old new : Row}
    {rowid : Int} (holds : state.Holds fact catalog) (passed : checkedUpdate catalog state position old new = .ok ())
    (rows : before.rows = state.rows) (oldRowid : old.rowid = rowid) (otherRows : other.rows = before.rows) :
    (other.changeRows position fun rows => rows.map fun row => if row.rowid == rowid then new else row).Holds fact catalog := by
  refine KeyState.holds_of_rows (other := state.changeRows position fun rows =>
    rows.map fun row => if row.rowid == rowid then new else row) (by simp only [KeyState.changeRows, otherRows, rows]) ?_
  refine KeyState.holds_changeRows holds fun table found => ?_
  have checked := checkedUpdate_ok facts passed found
  unfold LiteralData.replaceRow at checked
  rw [KeyState.table_rows found, oldRowid] at checked
  exact checked

/-- For every fact with {name}`TableFacts`, catalog, links, nested run, frame, position, change, positions, flag, state and
rowid: if the nested run keeps the invariant ({name}`NestedRun.Keeps`) and the state
satisfies {name}`KeyState.Holds`, the result of {name}`updateRow` keeps the invariant.
Proof sketch: the join points of the definition are proved in turn, from the last: the programs
keep the invariant ({name}`runPrograms_holds`), a failed check carries no state
({name}`checkedUpdate_error`), the foreign-key steps keep the rows ({name}`oldSteps_rows`,
{name}`newSteps_rows`), the write is {name}`updateWrite_holds`, and each action keeps the
invariant ({name}`runAction_holds`). -/
theorem updateRow_holds (facts : TableFacts fact) {catalog : Catalog} {links : List ForeignKeyLink} {nested : NestedRun}
    (keeps : nested.Keeps fact catalog) (frame : RowFrame) (position : Nat) (change : Row → Row)
    (assigned changed : List Nat) (record : Bool) {state : KeyState} (holds : state.Holds fact catalog) (rowid : Int) :
    ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
      (updateRow catalog links nested frame position change assigned changed record state rowid) := by
  unfold updateRow
  split
  · rename_i old name shape foundOld _
    have oldRowid : old.rowid = rowid := beq_iff_eq.mp (List.find?_some (p := fun row : Row => row.rowid == rowid) foundOld)
    extract_lets new event level children parents moved stale afterOldSteps afterChecks afterAlias
    have afterOldStepsOk : ∀ reached before : KeyState, reached.Holds fact catalog →
        checkedUpdate catalog reached position old new = .ok () → before.rows = reached.rows →
        ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog) (afterOldSteps before) := by
      intro reached before good passed same
      dsimp only [afterOldSteps]
      have removedOk := KeyState.holds_changeRows_sublist facts (KeyState.holds_of_rows same good)
        (position := position) (change := fun rows => rows.filter (·.rowid != rowid)) fun rows => List.filter_sublist
      have stored := fun checked : KeyState => ResultHolds.foldlM (fun acted link good =>
          runAction_holds (keeps frame.action) link link.key.onUpdate position old (some new) good) parents _
        (updateWrite_holds facts (other := ⟨before.rows, checked.counter, checked.acted,
          if record = true then checked.written ++ [new] else checked.written, checked.subqueried⟩) good passed same
          oldRowid rfl)
      split
      · exact ResultHolds.bind ((newSteps_rows _ _ _ _ _ _ _ _ _).holds_of_rows removedOk) fun checked _ =>
          ResultHolds.bind (stored checked) fun _ good =>
            ResultHolds.bind (runPrograms_holds keeps _ _ _ _ _ good) fun _ reached => reached
      · exact ResultHolds.bind (good := KeyState.Holds fact catalog) removedOk fun checked _ =>
          ResultHolds.bind (stored checked) fun _ good =>
            ResultHolds.bind (runPrograms_holds keeps _ _ _ _ _ good) fun _ reached => reached
    have afterChecksOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
        (afterChecks resumed) := by
      intro _
      dsimp only [afterChecks]
      refine ResultHolds.bind (good := fun reached : KeyState × Bool => reached.1.Holds fact catalog)
        (runPrograms_holds keeps _ _ _ _ _ holds) fun reached good => ?_
      obtain ⟨reachedState, ended⟩ := reached
      split
      · exact good
      · split
        · rename_i stop failed
          split
          · exact checkedUpdate_error failed
          · trivial
        · rename_i passed
          split
          · exact ResultHolds.bind (good := fun before : KeyState => before.rows = reachedState.rows)
              ((oldSteps_rows _ _ _ _ _ _ _).imp (fun _ kept => kept) fun _ undescribed => undescribed ▸ trivial)
              fun before same => afterOldStepsOk reachedState before good passed same
          · exact afterOldStepsOk reachedState reachedState good passed rfl
    have afterAliasOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
        (afterAlias resumed) := by
      intro _
      dsimp only [afterAlias]
      split
      · trivial
      · exact afterChecksOk ()
    split
    · trivial
    · exact afterAliasOk ()
  all_goals exact holds
