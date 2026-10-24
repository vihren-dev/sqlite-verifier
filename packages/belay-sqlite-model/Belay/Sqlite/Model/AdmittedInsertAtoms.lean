import Belay.Sqlite.Model.AdmittedInsertRows
import Belay.Sqlite.Model.AdmittedPlainWrites
import Belay.Sqlite.Model.AdmittedWriteReady

set_option doc.verso true

/-! The plain INSERT and the five table atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4). A
plain INSERT has no foreign key rules and no trigger programs. Each theorem says: if the atom holds in
the database, the effect of {lit}`runStatement` keeps it, on success and on an error with
{lit}`ExecutionError.constraintFail`. "Rowids distinct" needs nothing more, because the write checks the
rowids. The other four atoms assume that the run is ready ({lit}`StatementRun.ready`): the data check
of the INSERT ({lit}`LiteralData.insertReady`) then gives the width, the stored form and the range of
the new rows. A statement that is not ready can break "rowids in range", "rows wide" and "rows stored". "Rows aliased" also needs a valid catalog, which says that
the column of a rowid alias is not generated. {lit}`AdmittedAtomsCounterExamples` has an INSERT that breaks each of these atoms. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, target, rows of cells, returning list and subqueries,
and every database whose rowids are distinct: the effect of a plain INSERT satisfies "rowids distinct"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have distinct rowids in every table. Any other error requires
nothing. The statement does not need to be ready. Proof sketch: the write stores a table only after
the check {name}`LiteralData.rowidsDistinct` ({name}`runStatement_insert_atom`). -/
theorem runStatement_insert_rowidsDistinct (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (returning : List (Resolved.Expr × String))
    (subqueries : List Resolved.Query) {database : Database} (distinct : database.RowidsDistinct) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies
      Database.RowidsDistinct :=
  runStatement_insert_atom (atom := Table.RowidsDistinct) clock counters parameters target rows returning
    subqueries distinct fun _ _ passed => passed_rowidsDistinct passed

/-- For every clock value, counters, parameter list, target, rows of cells, returning list and subqueries,
and every database whose rowids are in range: if the run of a plain INSERT is ready, the effect satisfies
"rowids in range" ({name}`Effect.Satisfies`). Any error other than
{name}`ExecutionError.constraintFail` requires nothing. Proof sketch: the data check of the INSERT
contains {name}`Table.RowidsInRange` of the table after the INSERT ({name}`insertReady_parts`). -/
theorem runStatement_insert_rowidsInRange (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (returning : List (Resolved.Expr × String))
    (subqueries : List Resolved.Query) {database : Database} (inRange : database.RowidsInRange)
    (ready : (runStatement clock counters parameters (.insert target rows returning subqueries none)
      database).ready = true) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies
      Database.RowidsInRange :=
  runStatement_insert_atom (atom := Table.RowidsInRange) clock counters parameters target rows returning
    subqueries inRange fun _ found _ => (insertReady_parts (runStatement_insert_ready ready found)).2.2.2

/-- For every clock value, counters, parameter list, target, rows of cells, returning list and subqueries,
and every database whose rows are wide: if the run of a plain INSERT is ready, the effect satisfies
"rows wide" ({name}`Effect.Satisfies`): every row has one cell for each column. Any error other than
{name}`ExecutionError.constraintFail` requires nothing. Proof sketch: the data check of the INSERT
says that each supplied row has the width ({name}`insertReady_parts`), and a new row has the width of
its supplied row ({name}`LiteralData.inserted_wide`). -/
theorem runStatement_insert_rowsWide (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (returning : List (Resolved.Expr × String))
    (subqueries : List Resolved.Query) {database : Database} (wide : database.RowsWide)
    (ready : (runStatement clock counters parameters (.insert target rows returning subqueries none)
      database).ready = true) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies
      Database.RowsWide :=
  runStatement_insert_atom (atom := Table.RowsWide) clock counters parameters target rows returning
    subqueries wide fun _ found _ => LiteralData.inserted_wide (wide _ _ found)
      (insertReady_parts (runStatement_insert_ready ready found)).2.1

/-- For every clock value, counters, parameter list, target, rows of cells, returning list and subqueries,
and every database whose rows are stored: if the run of a plain INSERT is ready, the effect satisfies
"rows stored" ({name}`Effect.Satisfies`): every cell is in the stored form of its column. Any error
other than {name}`ExecutionError.constraintFail` requires nothing. Proof sketch: the data check of the
INSERT says that the table passes {name}`LiteralData.aliasReady` and each supplied row is stored
({name}`insertReady_parts`); then {name}`LiteralData.inserted_stored`. -/
theorem runStatement_insert_rowsStored (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (rows : List (List Resolved.Cell)) (returning : List (Resolved.Expr × String))
    (subqueries : List Resolved.Query) {database : Database} (stored : database.RowsStored)
    (ready : (runStatement clock counters parameters (.insert target rows returning subqueries none)
      database).ready = true) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies
      Database.RowsStored :=
  runStatement_insert_atom (atom := Table.RowsStored) clock counters parameters target rows returning
    subqueries stored fun _ found _ =>
      let parts := insertReady_parts (runStatement_insert_ready ready found)
      LiteralData.inserted_stored (stored _ _ found) parts.1 parts.2.2.1

/-- For every limits, clock value, counters, parameter list, target, rows of cells, returning list and
subqueries, and every database whose rows are aliased and whose catalog is valid under the limits: if the
run of a plain INSERT is ready, the effect satisfies "rows aliased" ({name}`Effect.Satisfies`): the
alias cell of every row is the integer rowid. Any error other than {name}`ExecutionError.constraintFail`
requires nothing. Proof sketch: a valid catalog does not generate the alias column
({name}`Database.aliasUngenerated`), each supplied row has the width ({name}`insertReady_parts`), and
{name}`LiteralData.inserted_aliased` gives the new rows. -/
theorem runStatement_insert_rowsAliased (limits : Limits) (clock : Int) (counters : Counters)
    (parameters : List Value) (target : Nat) (rows : List (List Resolved.Cell))
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (aliased : database.RowsAliased) (valid : database.catalog.Valid limits)
    (ready : (runStatement clock counters parameters (.insert target rows returning subqueries none)
      database).ready = true) :
    (runStatement clock counters parameters (.insert target rows returning subqueries none) database).effect.Satisfies
      Database.RowsAliased :=
  runStatement_insert_atom (atom := Table.RowsAliased) clock counters parameters target rows returning
    subqueries aliased fun _ found _ => LiteralData.inserted_aliased (aliased _ _ found)
      (Database.aliasUngenerated valid found) (insertReady_parts (runStatement_insert_ready ready found)).2.1

end Belay.Sqlite.Model
