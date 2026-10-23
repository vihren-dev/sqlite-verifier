import Belay.Sqlite.Model.RowEngineDelete
import Belay.Sqlite.Model.RowInsert

set_option doc.verso true

/-! The insert of a row keeps the invariant of the row engine for an atom (ADR 0022, D3,
slices 2 and 3): a failed constraint skips the row or stops with the state, REPLACE deletes rows,
and the write stores the table that {lit}`LiteralData.checkedRow` passed, which passed the
constraints with the unique keys of the written position. -/

namespace Belay.Sqlite.Model

variable {fact : Catalog → Nat → Table → Prop}

/-- For every fact, catalog, state and algorithm: if the state satisfies {name}`KeyState.Holds`,
the result of {name}`failedRow` keeps the invariant of the row engine. Proof sketch: IGNORE keeps
the state, FAIL and ROLLBACK stop with it, and the other algorithms carry no state. -/
theorem failedRow_holds {catalog : Catalog} {state : KeyState} (holds : state.Holds fact catalog)
    (algorithm : ConflictAlgorithm) :
    ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog) (failedRow state algorithm) := by
  cases algorithm <;> first | exact holds | trivial

/-- For every fact with {name}`TableFacts`, catalog, state, earlier state, target, entry, two
tables, row and written row: if the state satisfies {name}`KeyState.Holds`, the catalog has the
entry at the target, the earlier state has the first table at the target, and
{name}`LiteralData.checkedRow` with the holds keys of the entry passes the table with the
row appended and gives the second table, then the state with the second table's rows at the target
satisfies {name}`KeyState.Holds`. This is the write of {name}`insertRow`. Proof sketch: the first
table has the entry of the catalog there ({name}`KeyState.table_shape`), and so has each table
of the state at the target, and the checked table passed {name}`LiteralData.constraints` for the
keys of the entry ({name}`LiteralData.checkedRow_constraints`). -/
theorem insertWrite_holds (facts : TableFacts fact) {catalog : Catalog} {state earlier : KeyState} {target : Nat}
    {entry : CatalogTable} (entryFound : catalog.tableAt target = some entry) {current next : Table}
    {proposed : Row} {written : Option Row} (holds : state.Holds fact catalog)
    (earlierFound : (earlier.database catalog).table target = some current)
    (passed : LiteralData.checkedRow (catalog.uniqueKeys target entry)
      { shape := current.shape, rows := current.rows ++ [proposed] } proposed = .ok (next, written)) :
    (state.changeRows target fun _ => next.rows).Holds fact catalog := by
  refine KeyState.holds_changeRows holds fun other otherFound => ?_
  have currentEntry : current.shape = entry := by
    have first := KeyState.table_shape earlierFound
    rw [entryFound, Option.some.injEq] at first
    exact first.symm
  have otherEntry : other.shape = entry := by
    have first := KeyState.table_shape otherFound
    rw [entryFound, Option.some.injEq] at first
    exact first.symm
  obtain ⟨stored, checked⟩ := LiteralData.checkedRow_constraints passed
  subst stored
  rw [currentEntry] at checked
  rw [← otherEntry] at checked
  exact facts.constraints catalog target _ checked

/-- For every fact with {name}`TableFacts`, catalog, links, nested run, frame, target, policy, clauses, flags, state and
values: if the nested run keeps the invariant ({name}`NestedRun.Keeps`) and the state
satisfies {name}`KeyState.Holds`, the result of {name}`insertRow` keeps the invariant.
Proof sketch: the join points of the definition are proved in turn, from the last: the programs
keep the invariant ({name}`runPrograms_holds`), a failed constraint is
{name}`failedRow_holds`, DO NOTHING keeps the state, the rows that REPLACE deletes are
{name}`deleteRow_holds`, the foreign-key steps keep the rows ({name}`newSteps_rows`), and the
write is {name}`insertWrite_holds`. -/
theorem insertRow_holds (facts : TableFacts fact) {catalog : Catalog} {links : List ForeignKeyLink} {nested : NestedRun}
    (keeps : nested.Keeps fact catalog) (frame : RowFrame) (target : Nat) (policy : Resolved.ConflictPolicy)
    (clauses : List Resolved.ConflictClause) (multiWrite record : Bool) {state : KeyState}
    (holds : state.Holds fact catalog) (values : List Value) :
    ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
      (insertRow catalog links nested frame target policy clauses multiWrite record state values) := by
  unfold insertRow
  split
  · rename_i table found
    extract_lets afterTypes afterAlias
    have afterTypesOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
        (afterTypes resumed) := by
      intro _
      dsimp (config := { zeta := false }) only [afterTypes]
      refine ResultHolds.bind (good := fun reached : KeyState × Bool => reached.1.Holds fact catalog)
        (runPrograms_holds keeps _ _ _ _ _ holds) fun reached good => ?_
      obtain ⟨reachedState, ended⟩ := reached
      split
      · exact good
      · split
        · rename_i current currentFound
          extract_lets keys proposed replaced afterCount afterClause afterChecks afterBounded
          have afterCountOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
              (afterCount resumed) := by
            intro _
            dsimp only [afterCount]
            refine ResultHolds.bind (ResultHolds.foldlM (good := KeyState.Holds fact catalog) (fun reached row held =>
              deleteRow_holds facts keeps { frame with algorithm := some .replace } target false false frame.recursive held row.rowid) replaced _ good)
                fun deleted deletedGood => ?_
            refine ResultHolds.bind ((newSteps_rows _ _ _ _ _ _ _ _ _).holds_of_rows deletedGood)
              fun checked checkedGood => ?_
            split
            · rename_i inner innerFound
              split
              · trivial
              · rename_i next written passed
                exact ResultHolds.bind (runPrograms_holds keeps _ _ _ _ _
                  (KeyState.holds_of_rows rfl (insertWrite_holds facts (KeyState.table_shape currentFound) checkedGood innerFound passed)))
                  fun _ reached => reached
            · trivial
          have afterClauseOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
              (afterClause resumed) := by
            intro _
            dsimp only [afterClause]
            split
            · exact failedRow_holds good _
            · split
              · trivial
              · exact afterCountOk ()
          have afterChecksOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
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
          have afterBoundedOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
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
    have afterAliasOk : ∀ resumed : Unit, ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog)
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
