import Belay.Sqlite.Model.RowEngineDelete
import Belay.Sqlite.Model.RowInsert
import Belay.Sqlite.Model.RowCreditHolds

set_option doc.verso true

/-! The insert of a row keeps the invariant of the row engine for an atom (ADR 0022, D3,
slices 2 and 3): a failed constraint skips the row or stops with the state, REPLACE deletes rows,
and the write stores the table that {lit}`LiteralData.checkedRow` passed, which passed the
constraints with the unique keys of the written position. -/

namespace Belay.Sqlite.Model

variable {invariant : Database → Prop}

/-- For every invariant, catalog, state and algorithm: if the state satisfies {name}`KeyState.Holds`,
the result of {name}`failedRow` keeps the invariant of the row engine. Proof sketch: IGNORE keeps
the state, FAIL and ROLLBACK stop with it, and the other algorithms carry no state. -/
theorem failedRow_holds {catalog : Catalog} {state : KeyState} (holds : state.Holds invariant catalog)
    (algorithm : ConflictAlgorithm) :
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog) (failedRow state algorithm) := by
  cases algorithm <;> first | exact holds | trivial

/-- For every invariant with {name}`WriteLaws`, catalog, state, target, entry, two tables, row and written
row: if the state satisfies {name}`KeyState.Holds`, the catalog has the entry at the target, the database
of the state has the first table at the target, the row is admitted for the shape of the first table
({name}`LiteralData.rowAdmitted`), and {name}`LiteralData.checkedRow` with the keys of the entry passes the
table with the row appended and gives the second table, then the state with the second table's rows at
the target satisfies {name}`KeyState.Holds`. This is the write of {name}`insertRow`. Proof sketch: the first
table is the entry of the catalog with the rows of the state at the target ({name}`KeyState.table_shape`,
{name}`KeyState.table_rows`), the checked table passed {name}`LiteralData.constraints` and
{name}`LiteralData.rowidsDistinct` for the keys of the entry ({name}`LiteralData.checkedRow_passed`), and
each of its rows is a row of the state or the admitted row; that is the write of {name}`WriteLaws`. -/
theorem insertWrite_holds (laws : WriteLaws invariant) {catalog : Catalog} {state : KeyState} {target : Nat}
    {entry : CatalogTable} (entryFound : catalog.tableAt target = some entry) {current next : Table}
    {proposed : Row} {written : Option Row} (holds : state.Holds invariant catalog)
    (found : (state.database catalog).table target = some current)
    (admitted : LiteralData.rowAdmitted current.shape proposed = true)
    (passed : LiteralData.checkedRow (catalog.uniqueKeys target entry)
      { shape := current.shape, rows := current.rows ++ [proposed] } proposed = .ok (next, written)) :
    (state.changeRows target fun _ => next.rows).Holds invariant catalog := by
  have currentEntry : current.shape = entry := by
    have first := KeyState.table_shape found
    rw [entryFound, Option.some.injEq] at first
    exact first.symm
  have currentRows := KeyState.table_rows found
  obtain ⟨stored, checked⟩ := LiteralData.checkedRow_passed passed
  subst stored
  rw [currentEntry] at checked
  refine KeyState.holds_write laws holds found ?_ ?_
  · rw [currentEntry]
    exact checked
  · intro row member
    rw [← currentRows]
    simp only [List.mem_append, List.mem_singleton] at member ⊢
    rcases member with old | same
    · exact .inl old
    · exact .inr (same ▸ admitted)

/-- For every invariant with {name}`WriteLaws`, catalog, links, nested run, frame, target, state and
row: if the nested run keeps the invariant ({name}`NestedRun.Keeps`) and the state satisfies
{name}`KeyState.Holds`, the result of {name}`replaceDelete` keeps the invariant. Proof sketch:
{name}`deleteRow_holds`, and the count of own rows that {name}`replaceDelete` restores is no row
({name}`KeyResult.mapState_holds`). -/
theorem replaceDelete_holds (laws : WriteLaws invariant) {catalog : Catalog} {links : List ForeignKeyLink}
    {nested : NestedRun} (keeps : nested.Keeps invariant catalog) (frame : RowFrame) (target : Nat) {state : KeyState}
    (holds : state.Holds invariant catalog) (row : Row) :
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
      (replaceDelete catalog links nested frame target state row) :=
  KeyResult.mapState_holds (change := fun deleted : KeyState => { deleted with own := state.own }) (fun _ => rfl)
    (deleteRow_holds laws keeps { frame with algorithm := some .replace } target
      false false frame.recursive holds row.rowid)

/-- For every invariant with {name}`WriteLaws`, catalog, links, nested run, frame, target, policy, clauses, flags, state and
values: if the nested run keeps the invariant ({name}`NestedRun.Keeps`) and the state
satisfies {name}`KeyState.Holds`, the result of {name}`insertRow` keeps the invariant.
Proof sketch: the join points of the definition are proved in turn, from the last: the programs
keep the invariant ({name}`runPrograms_holds`), a failed constraint is
{name}`failedRow_holds`, DO NOTHING keeps the state, the rows that REPLACE deletes are
{name}`replaceDelete_holds`, the foreign-key steps keep the rows ({name}`newSteps_rows`), and the
write is {name}`insertWrite_holds`. -/
theorem insertRow_holds (laws : WriteLaws invariant) {catalog : Catalog} {links : List ForeignKeyLink} {nested : NestedRun}
    (keeps : nested.Keeps invariant catalog) (frame : RowFrame) (target : Nat) (policy : Resolved.ConflictPolicy)
    (clauses : List Resolved.ConflictClause) (multiWrite record : Bool) {state : KeyState}
    (holds : state.Holds invariant catalog) (values : List Value) :
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
      (insertRow catalog links nested frame target policy clauses multiWrite record state values) := by
  unfold insertRow
  split
  · rename_i table found
    extract_lets afterTypes afterAlias
    have afterTypesOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
        (afterTypes resumed) := by
      intro _
      dsimp (config := { zeta := false }) only [afterTypes]
      refine ResultHolds.bind (good := fun reached : KeyState × Bool => reached.1.Holds invariant catalog)
        (runPrograms_holds keeps _ _ _ _ _ holds) fun reached good => ?_
      obtain ⟨reachedState, ended⟩ := reached
      split
      · exact good
      · split
        · rename_i current currentFound
          extract_lets keys proposed replaced afterCount afterClause afterChecks afterBounded
          have afterCountOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
              (afterCount resumed) := by
            intro _
            dsimp only [afterCount]
            refine ResultHolds.bind (ResultHolds.foldlM (good := KeyState.Holds invariant catalog) (fun reached row held =>
              replaceDelete_holds laws keeps frame target held row) replaced _ good)
                fun deleted deletedGood => ?_
            refine ResultHolds.bind ((newSteps_rows _ _ _ _ _ _ _ _ _).holds_of_rows deletedGood)
              fun checked checkedGood => ?_
            split
            · trivial
            · split
              · rename_i inner innerFound
                split
                · trivial
                · rename_i next written passed
                  split
                  · trivial
                  · rename_i admitted
                    exact ResultHolds.bind (runPrograms_holds keeps _ _ _ _ _
                      (KeyState.holds_of_rows rfl (insertWrite_holds laws (KeyState.table_shape currentFound)
                        checkedGood innerFound (by simpa using admitted) passed)))
                      fun _ reached => reached
              · trivial
          have afterClauseOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
              (afterClause resumed) := by
            intro _
            dsimp only [afterClause]
            split
            · exact failedRow_holds good _
            · split
              · trivial
              · exact afterCountOk ()
          have afterChecksOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
              (afterChecks resumed) := by
            intro _
            dsimp only [afterChecks]
            split
            · exact failedRow_holds good _
            · split
              · split
                · exact good
                · trivial
              · exact afterClauseOk ()
          have afterBoundedOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
              (afterBounded resumed) := by
            intro _
            dsimp only [afterBounded]
            split
            · exact failedRow_holds good _
            · split
              · trivial
              · exact afterChecksOk ()
          split
          · trivial
          · exact afterBoundedOk ()
        · trivial
    have afterAliasOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
        (afterAlias resumed) := by
      intro _
      dsimp only [afterAlias]
      split
      · trivial
      · exact afterTypesOk ()
    split
    · trivial
    · exact afterAliasOk ()
  · trivial
