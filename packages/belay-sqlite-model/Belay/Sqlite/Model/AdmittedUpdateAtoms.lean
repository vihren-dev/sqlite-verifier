import Belay.Sqlite.Model.AdmittedPlainWrites
import Belay.Sqlite.Model.AdmittedUpdatedTable
import Belay.Sqlite.Model.AdmittedWriteReady

set_option doc.verso true

/-! The plain UPDATE and the five table atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4). A
plain UPDATE has no foreign key rules and no trigger programs. Each theorem says: if the atom holds in
the database, the effect of {lit}`runStatement` keeps it, on success and on an error with
{lit}`ExecutionError.constraintFail`. "Rowids distinct" needs nothing more, because the write checks the
rowids. "Rows wide" and "rows stored" need nothing more either: an UPDATE keeps the width, and it
stores each new cell. "Rows aliased" needs a valid catalog, which says that the column of a rowid alias
is not generated; an UPDATE that would set the alias to a value that is not an integer fails before it
writes ({lit}`LiteralData.updateMismatch`). "Rowids in range" assumes that the run is ready
({lit}`StatementRun.ready`), because an UPDATE can move a row to a rowid out of range. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, parameter list, target, assignments, filter, returning list and
subqueries, and every database whose rowids are distinct: the effect of a plain UPDATE satisfies "rowids
distinct" ({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have distinct rowids in every table. Any other error requires
nothing. The statement does not need to be ready. Proof sketch: the write stores a table only after
the check {name}`LiteralData.rowidsDistinct` ({name}`runStatement_update_atom`). -/
theorem runStatement_update_rowidsDistinct (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (assignments : List (Nat × Resolved.Expr)) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (distinct : database.RowidsDistinct) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).effect.Satisfies Database.RowidsDistinct :=
  runStatement_update_atom (atom := Table.RowidsDistinct) clock counters parameters target assignments filter
    returning subqueries distinct fun _ _ _ passed => passed_rowidsDistinct passed

/-- For every clock value, counters, parameter list, target, assignments, filter, returning list and
subqueries, and every database whose rowids are in range: if the run of a plain UPDATE is ready, the
effect satisfies "rowids in range" ({name}`Effect.Satisfies`). Any error other than
{name}`ExecutionError.constraintFail` requires nothing. Proof sketch: the data check of the UPDATE
contains {name}`Table.RowidsInRange` of the updated table ({name}`updateReady_parts`). -/
theorem runStatement_update_rowidsInRange (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (assignments : List (Nat × Resolved.Expr)) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (inRange : database.RowidsInRange)
    (ready : (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).ready = true) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).effect.Satisfies Database.RowidsInRange :=
  runStatement_update_atom (atom := Table.RowidsInRange) clock counters parameters target assignments filter
    returning subqueries inRange fun _ found _ _ => (updateReady_parts (runStatement_update_ready ready found)).2

/-- For every clock value, counters, parameter list, target, assignments, filter, returning list and
subqueries, and every database whose rows are wide: the effect of a plain UPDATE satisfies "rows wide"
({name}`Effect.Satisfies`): every row has one cell for each column. Any error other than
{name}`ExecutionError.constraintFail` requires nothing. The statement does not need to be ready.
Proof sketch: {name}`LiteralData.updated_wide`. -/
theorem runStatement_update_rowsWide (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (assignments : List (Nat × Resolved.Expr)) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (wide : database.RowsWide) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).effect.Satisfies Database.RowsWide :=
  runStatement_update_atom (atom := Table.RowsWide) clock counters parameters target assignments filter
    returning subqueries wide fun _ found _ _ => LiteralData.updated_wide (wide _ _ found)

/-- For every clock value, counters, parameter list, target, assignments, filter, returning list and
subqueries, and every database whose rows are stored: the effect of a plain UPDATE satisfies "rows
stored" ({name}`Effect.Satisfies`): every cell is in the stored form of its column. Any error other than
{name}`ExecutionError.constraintFail` requires nothing. The statement does not need to be ready.
Proof sketch: {name}`LiteralData.updated_stored`. -/
theorem runStatement_update_rowsStored (clock : Int) (counters : Counters) (parameters : List Value)
    (target : Nat) (assignments : List (Nat × Resolved.Expr)) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) (subqueries : List Resolved.Query) {database : Database}
    (stored : database.RowsStored) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).effect.Satisfies Database.RowsStored :=
  runStatement_update_atom (atom := Table.RowsStored) clock counters parameters target assignments filter
    returning subqueries stored fun _ found _ _ => LiteralData.updated_stored (stored _ _ found)

/-- For every limits, clock value, counters, parameter list, target, assignments, filter, returning list
and subqueries, and every database whose rows are aliased and whose catalog is valid under the limits:
the effect of a plain UPDATE satisfies "rows aliased" ({name}`Effect.Satisfies`): the alias cell of every
row is the integer rowid. Any error other than {name}`ExecutionError.constraintFail` requires nothing.
The statement does not need to be ready. Proof sketch: a valid catalog does not generate the alias
column ({name}`Database.aliasUngenerated`); an UPDATE that stores a table has no refused alias
({name}`runStatement_update_atom`), so {name}`LiteralData.updated_aliased` applies. -/
theorem runStatement_update_rowsAliased (limits : Limits) (clock : Int) (counters : Counters)
    (parameters : List Value) (target : Nat) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (returning : List (Resolved.Expr × String))
    (subqueries : List Resolved.Query) {database : Database} (aliased : database.RowsAliased)
    (valid : database.catalog.Valid limits) :
    (runStatement clock counters parameters (.update target assignments filter returning subqueries none)
      database).effect.Satisfies Database.RowsAliased :=
  runStatement_update_atom (atom := Table.RowsAliased) clock counters parameters target assignments filter
    returning subqueries aliased fun _ found accepted _ =>
      LiteralData.updated_aliased (aliased _ _ found) (Database.aliasUngenerated valid found) accepted

end Belay.Sqlite.Model
