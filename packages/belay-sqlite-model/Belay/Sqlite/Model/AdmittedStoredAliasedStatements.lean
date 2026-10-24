import Belay.Sqlite.Model.AdmittedAddColumnLaws
import Belay.Sqlite.Model.AdmittedInsertAtoms
import Belay.Sqlite.Model.AdmittedTableAtomStatement
import Belay.Sqlite.Model.AdmittedUpdateAtoms
import Belay.Sqlite.Model.AdmittedUpsertAtoms

set_option doc.verso true

/-! The statement theorems of the atoms "rows stored" and "rows aliased" (ADR 0022, D3, slice 4).
ADD COLUMN needs the width of the rows for "rows stored" (the new cell is read by position), and both
atoms need a valid catalog or the support check for the rows that a write computes. The theorems cover
every form of a statement, also with foreign key rules and trigger programs: the row engine checks every
row that it writes (owner decision M of the status file, finding 16). -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, resolved statement and database: if the database
satisfies "rows stored" ({name}`Database.RowsStored`) and "rows wide" ({name}`Database.RowsWide`), the
run of the statement is ready ({name}`StatementRun.ready`), the effect of {name}`runStatement` satisfies "rows stored"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have every cell stored for its column, and any other error
requires nothing. It assumes no other atom. Proof sketch: {name}`runStatement_tableAtom` with
{name}`rowsStoredLaws`, the rows of ADD COLUMN ({name}`Table.RowsStored.appendColumns`, which reads the
width) and the theorems of the three row forms without rules. -/
theorem runStatement_rowsStored (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) {database : Database} (stored : database.RowsStored) (wide : database.RowsWide)
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsStored :=
  runStatement_tableAtom Table.rowsStoredAtom rowsStoredLaws clock counters parameters statement stored
    (fun target _ table _ _ found _ => Table.RowsStored.appendColumns (wide target table found)
      (stored target table found) _) fun writes => by
      rcases writes with ⟨target, rows, returning, subqueries, rfl⟩ | ⟨target, assignments, filter, returning, subqueries, rfl⟩ |
        ⟨target, rows, clauses, returning, algorithm, subqueries, rfl⟩
      · exact runStatement_insert_rowsStored clock counters parameters target rows returning subqueries stored ready
      · exact runStatement_update_rowsStored clock counters parameters target assignments filter returning subqueries stored
      · exact runStatement_upsert_rowsStored clock counters parameters target rows clauses returning algorithm subqueries
          stored ready

/-- For every limits, clock value, counters, parameter list, resolved statement and database: if the
database satisfies "rows aliased" ({name}`Database.RowsAliased`), its catalog is valid under the limits
({name}`Catalog.Valid`) and the run of the statement is ready ({name}`StatementRun.ready`), the effect of {name}`runStatement` satisfies "rows
aliased" ({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have the rowid in the alias cell of every row of a table with a
rowid alias, and any other error requires nothing. Proof sketch: {name}`runStatement_tableAtom` with
{name}`rowsAliasedLaws`, the rows of ADD COLUMN ({name}`Table.RowsAliased.appendColumns`) and the theorems
of the three row forms without rules, which read the alias column from the valid catalog. -/
theorem runStatement_rowsAliased (limits : Limits) (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) {database : Database} (aliased : database.RowsAliased)
    (valid : database.catalog.Valid limits)
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsAliased :=
  runStatement_tableAtom Table.rowsAliasedAtom rowsAliasedLaws clock counters parameters statement aliased
    (fun target _ table _ _ found _ => Table.RowsAliased.appendColumns (aliased target table found) _) fun writes => by
      rcases writes with ⟨target, rows, returning, subqueries, rfl⟩ | ⟨target, assignments, filter, returning, subqueries, rfl⟩ |
        ⟨target, rows, clauses, returning, algorithm, subqueries, rfl⟩
      · exact runStatement_insert_rowsAliased limits clock counters parameters target rows returning subqueries aliased
          valid ready
      · exact runStatement_update_rowsAliased limits clock counters parameters target assignments filter returning
          subqueries aliased valid
      · exact runStatement_upsert_rowsAliased limits clock counters parameters target rows clauses returning algorithm
          subqueries aliased valid ready

end Belay.Sqlite.Model
