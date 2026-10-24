import Belay.Sqlite.Model.AdmittedAddColumnLaws
import Belay.Sqlite.Model.AdmittedInsertAtoms
import Belay.Sqlite.Model.AdmittedTableAtomStatement
import Belay.Sqlite.Model.AdmittedUpdateAtoms
import Belay.Sqlite.Model.AdmittedUpsertAtoms

set_option doc.verso true

/-! The statement theorems of the atoms "rowids in range" and "rows wide" (ADR 0022, D3, slice 4).
Both depend on the support check: the INSERT reads the rowid and the width from the rows that it
writes, and the check says what they are ({lit}`StatementRun.ready`). The theorems cover every form of a
statement, also with foreign key rules and trigger programs: the row engine checks every row that it
writes (owner decision M of the status file, finding 16). -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, resolved statement and database: if the database
satisfies "rowids in range" ({name}`Database.RowidsInRange`) and the run of the statement is ready
({name}`StatementRun.ready`), the effect of {name}`runStatement` satisfies "rowids in range"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have a valid rowid ({name}`validRowid`) in every row, and any other error requires nothing.
It assumes no other atom. Proof sketch: {name}`runStatement_tableAtom` with {name}`rowidsInRangeLaws`, the
rowids of ADD COLUMN ({name}`Table.RowidsInRange.appendColumns`) and the theorems of the three row forms
without rules. -/
theorem runStatement_rowidsInRange (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) {database : Database} (inRange : database.RowidsInRange)
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowidsInRange :=
  runStatement_tableAtom Table.rowidsInRangeAtom rowidsInRangeLaws clock counters parameters statement inRange
    (fun target _ table _ _ found _ => Table.RowidsInRange.appendColumns (inRange target table found) _) fun writes => by
      rcases writes with ⟨target, rows, returning, subqueries, rfl⟩ | ⟨target, assignments, filter, returning, subqueries, rfl⟩ |
        ⟨target, rows, clauses, returning, algorithm, subqueries, rfl⟩
      · exact runStatement_insert_rowidsInRange clock counters parameters target rows returning subqueries inRange ready
      · exact runStatement_update_rowidsInRange clock counters parameters target assignments filter returning subqueries
          inRange ready
      · exact runStatement_upsert_rowidsInRange clock counters parameters target rows clauses returning algorithm
          subqueries inRange ready

/-- For every clock value, counters, parameter list, resolved statement and database: if the database
satisfies "rows wide" ({name}`Database.RowsWide`) and the run of the statement is ready
({name}`StatementRun.ready`), the effect of {name}`runStatement` satisfies "rows wide"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have a cell for each column in every row, and any other error
requires nothing. It assumes no other atom. Proof sketch: {name}`runStatement_tableAtom` with
{name}`rowsWideLaws`, the rows of ADD COLUMN ({name}`Table.RowsWide.appendColumns`) and the theorems of the
three row forms without rules. -/
theorem runStatement_rowsWide (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) {database : Database} (wide : database.RowsWide)
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsWide :=
  runStatement_tableAtom Table.rowsWideAtom rowsWideLaws clock counters parameters statement wide
    (fun target _ table _ _ found _ => Table.RowsWide.appendColumns (wide target table found) _) fun writes => by
      rcases writes with ⟨target, rows, returning, subqueries, rfl⟩ | ⟨target, assignments, filter, returning, subqueries, rfl⟩ |
        ⟨target, rows, clauses, returning, algorithm, subqueries, rfl⟩
      · exact runStatement_insert_rowsWide clock counters parameters target rows returning subqueries wide ready
      · exact runStatement_update_rowsWide clock counters parameters target assignments filter returning subqueries wide
      · exact runStatement_upsert_rowsWide clock counters parameters target rows clauses returning algorithm subqueries
          wide ready

end Belay.Sqlite.Model
