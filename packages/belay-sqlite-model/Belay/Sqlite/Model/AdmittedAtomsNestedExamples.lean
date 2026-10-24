import Belay.Sqlite.Model.AdmittedAtomsCounterExamples

set_option doc.verso true

/-! A statement with trigger programs whose nested write is not described (ADR 0022, slice 4, part 2;
finding 16 of the status file and the owner decision M), checked by the kernel. An INSERT runs an AFTER
INSERT trigger whose UPDATE would write the rowid {lit}`2 ^ 70`, which is out of range, into a second
table, and an AFTER UPDATE trigger of that table would stop the write with {lit}`RAISE(FAIL)`. Before the
decision the run was ready and the database that the error {lit}`constraintFail` keeps had the rowid out of
range. Now the row engine tests every row that it writes ({lit}`LiteralData.rowAdmitted`), so the run is not
ready and ends as {lit}`unmodeled` with the input database. -/

namespace Belay.Sqlite.Model.AdmittedAtomsNestedExamples

open Belay.Sqlite.Model AdmittedAtomsCounterExamples

/-- The table {lit}`u(id INTEGER PRIMARY KEY)` with the row {lit}`(1)` at the rowid 1. -/
def keyedTable : Table :=
  { shape := { columns := [{ columnA with name := Identifier.ofString "id" }], primaryKey := [0], rowidAlias := some 0 },
    rows := [{ rowid := 1, values := [.integer 1] }] }

/-- The database with {name}`emptyTable` at position 0 and {name}`keyedTable` at position 1. -/
def twoTables : Database :=
  .ofTables [(Identifier.ofString "s", emptyTable), (Identifier.ofString "u", keyedTable)]

/-- The program of an AFTER INSERT trigger on the table at position 0: an UPDATE of the table at
position 1 that sets the alias to the integer {lit}`2 ^ 70`. A resolved program can hold this integer,
although the resolver does not make it from SQL text. -/
def updateProgram : Resolved.Program :=
  { trigger := 2, table := 0, time := .after, event := .insert, width := 1, condition := none,
    body := [.update 1 [(0, .literal (.integer (2 ^ 70)))] none []] }

/-- The program of an AFTER UPDATE trigger on the table at position 1: {lit}`RAISE(FAIL)`. -/
def raiseProgram : Resolved.Program :=
  { trigger := 3, table := 1, time := .after, event := .update none, width := 1, condition := none,
    body := [.raise none [] (some .fail)] }

/-- The INSERT of one row into the table at position 0 with the two programs. -/
def nestedInsert : Resolved.Statement :=
  .insert 0 [[.value (.integer 1)]] [] [] (some { depth := 3, keys := false, programs := [updateProgram, raiseProgram] })

-- The database {name}`twoTables` has its rowids in range.
example : twoTables.RowidsInRange := by
  intro position table found row member
  rcases position with _ | _ | position
  · have same : table = emptyTable := Option.some.inj (found.symm.trans rfl)
    subst same
    simp [emptyTable] at member
  · have same : table = keyedTable := Option.some.inj (found.symm.trans rfl)
    subst same
    simp only [keyedTable, List.mem_singleton] at member
    subst member
    exact ⟨by decide, by decide⟩
  · have none : twoTables.table (position + 2) = none := by
      simp [twoTables, Database.ofTables, Database.table, Catalog.tableAt]
    rw [none] at found
    cases found
-- The nested UPDATE would write the rowid 2 ^ 70. The row fails the test, so the run is not ready and
-- the error is `unmodeled`, which keeps the input database.
example : (runStatement 0 {} [] nestedInsert twoTables).ready = false := by decide +kernel
example : (runStatement 0 {} [] nestedInsert twoTables).effect = .error (.unmodeled, twoTables) := by rfl
-- The effect satisfies every property of databases, because it is neither a success nor a `constraintFail`.
example (property : Database → Prop) : (runStatement 0 {} [] nestedInsert twoTables).effect.Satisfies property := by
  intro database kept
  have effect : (runStatement 0 {} [] nestedInsert twoTables).effect = .error (.unmodeled, twoTables) := by rfl
  rw [effect] at kept
  rcases kept with same | same <;> cases same
-- The row of the nested UPDATE is not admitted: its rowid is out of range.
example : LiteralData.rowAdmitted keyedTable.shape { rowid := 2 ^ 70, values := [.integer (2 ^ 70)] } = false := by
  decide +kernel

end Belay.Sqlite.Model.AdmittedAtomsNestedExamples
