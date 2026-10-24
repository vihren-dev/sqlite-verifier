import Belay.Sqlite.Model.ForeignKeySatisfied
import Belay.Sqlite.Model.Resolution.ForeignKeyPlan
import Belay.Sqlite.Model.Execution

set_option doc.verso true

/-! The foreign-key steps of one row (ADR 0018, D4), as SQLite's {lit}`sqlite3FkCheck` runs
them, over one counter of violations for the whole statement. Before a row is deleted or
updated, each key of the row that has no parent takes one from the counter, when the counter
is not zero ({lit}`OP_FkIfZero`), and each child row of the row adds one. Before a row is
inserted, or the new row of an update, each key of the row without a parent adds one, and each
child row of the row takes one, when the counter is not zero. A statement that ends with a
counter other than zero fails. -/

namespace Belay.Sqlite.Model

/-- The state of a write that checks foreign keys: the stored rows of each catalog position,
the counter of violations, the positions of the tables that the actions changed, and the rows
that the statement itself wrote, in order. The catalog does not change during the write, so it
is not part of the state. Start from the rows of the input database with the other fields
empty. -/
structure KeyState where
  /-- The stored rows of each catalog position so far ({name}`Database.rows`). -/
  rows : List (List Row)
  /-- SQLite's counter of immediate foreign-key violations ({lit}`nFkConstraint`). -/
  counter : Int := 0
  /-- The catalog positions of the tables whose rows an action changed. -/
  acted : List Nat := []
  /-- The rows that the statement wrote: the new rows of INSERT and UPDATE, the old rows of
  DELETE. -/
  written : List Row := []
  /-- Whether a statement of a trigger's body with subqueries ran (ADR 0018, D5), whose
  subqueries read the tables while the write changes them. -/
  subqueried : Bool := false
  /-- The rows that the write at the current level counted: the rows that it inserted, updated
  or deleted, except the rows that REPLACE deletes (ADR 0024, D2). At the top level they are the
  rows of {lit}`changes()`. -/
  own : Nat := 0
  /-- The rows of the nested writes of programs and actions that completed, which count for
  {lit}`total_changes()` also when the statement fails later. -/
  credited : Nat := 0
  /-- The rowid of the last row that the statement itself inserted into a table with a rowid,
  which {lit}`last_insert_rowid()` takes; none when it inserted none. -/
  inserted : Option Int := none

/-- The failure of a row that stops the statement and keeps the rows that it reached: the FAIL
algorithm or the ROLLBACK algorithm of a failed constraint or of {lit}`RAISE`. -/
inductive StopAlgorithm where
  /-- FAIL ({lean}`ExecutionError.constraintFail`). -/
  | fail
  /-- ROLLBACK ({lean}`ExecutionError.constraintRollback`). -/
  | rollback
  deriving Repr, DecidableEq

/-- Why a write that runs row by row stops: the error of the statement, a FAIL or ROLLBACK
failure with the state that it reached, or a case that the model does not describe, such as
writes nested deeper than the fuel. -/
inductive KeyStop where
  /-- The statement fails with the error and keeps nothing; the state is the state when it
  failed, which gives its counts (ADR 0024, D2). -/
  | error (reason : ExecutionError) (state : KeyState)
  /-- The statement stops with the algorithm and the state that it reached. -/
  | stopped (algorithm : StopAlgorithm) (state : KeyState)
  /-- The model does not describe the statement on the database. -/
  | undescribed

/-- The database of the state over the catalog. -/
def KeyState.database (state : KeyState) (catalog : Catalog) : Database := { catalog, rows := state.rows }

/-- The state with the rows at a position changed. -/
def KeyState.changeRows (state : KeyState) (position : Nat) (change : List Row → List Row) : KeyState :=
  { state with rows := state.rows.set position (change (state.rows.getD position [])) }

/-- The child rows of a parent row for a located link, in the child table's scan order
({name}`Belay.Sqlite.Model.Table.scanRows`), among the rows of the table and the extra rows: those of
{name}`childMatches`, except the parent row itself in a table that references itself when
{lit}`exclude` is set ({lit}`fkScanChildren` for a removed row). -/
def childRows (database : Database) (link : ForeignKeyLink) (key : ParentKey) (parent : Nat) (row : Row)
    (extra : List Row) (exclude : Bool) : List Row :=
  match database.table link.child, database.catalog.tableAt parent with
  | some child, some shape =>
    ({ child with rows := child.rows ++ extra }).scanRows.filter fun candidate =>
      childMatches child.shape shape link key row candidate &&
        !(exclude && link.child == parent && candidate.rowid == row.rowid)
  | none, _ | some _, none => []

/-- The steps before a row of the table at the position is deleted, or before the old row of
an update is replaced: for each key of the row, newest first, one less when the counter is not
zero, no key value is NULL, and no parent row is found; then for each key that references the
table, one more for each child row of the row, except the row itself. With {lit}`ignore`, the
DELETE of DROP TABLE, a key whose parent table does not exist takes one for a row without a
NULL key value, also when the counter is zero, and a key without a parent key is skipped; in
any other write such a key is not described. -/
def oldSteps (catalog : Catalog) (state : KeyState) (position : Nat) (row : Row) (children parents : List ForeignKeyLink) (ignore : Bool) :
    Except KeyStop KeyState := do
  let state ← children.foldlM (fun (state : KeyState) (link : ForeignKeyLink) => match link.parent with
    | .located parent key =>
      if state.counter == 0 || link.hasNull row.values then pure state else
      match catalog.tableAt parent with
      | none => throw .undescribed
      | some shape => if parentFound shape key link row.values ((state.database catalog).rowsAt parent) none then pure state
        else pure { state with counter := state.counter - 1 }
    | .missing => if !ignore then throw .undescribed
      else pure (if link.hasNull row.values then state else { state with counter := state.counter - 1 })
    | .mismatch _ => if ignore then pure state else throw .undescribed) state
  parents.foldlM (fun (state : KeyState) (link : ForeignKeyLink) => match link.parent with
    | .located _ key =>
      pure { state with counter := state.counter + (childRows (state.database catalog) link key position row [] true).length }
    | .mismatch _ | .missing => if ignore then pure state else throw .undescribed) state

/-- The rows of a table that references itself that SQLite's lookup still finds while the new
row of an update is checked, besides the table's rows: the old row, when the table keeps its
record ({lit}`stale`), for a rowid key, or for a key of columns whose index the update does not
change. -/
def staleRows (key : ParentKey) (stale : Option Row) (changed : List Nat) : List Row :=
  match key with
  | .rowid => stale.toList
  | .columns pairs => if pairs.any (changed.contains ·.2) then [] else stale.toList

/-- The steps before a new row of the table at the position is inserted, or before the new row
of an update is written: for each key of the row, newest first, one more when no key value is
NULL and no parent row is found, where a row of a table that references itself may be its own
parent; then, when {lit}`scan` is set, for each key that references the table, one less for
each child row of the row while the counter is not zero. The old row of an update that SQLite
keeps in the table ({lit}`stale`, see {name}`staleRows`) is still found by the lookups and the
scans of the table itself. -/
def newSteps (catalog : Catalog) (state : KeyState) (position : Nat) (row : Row) (children parents : List ForeignKeyLink) (scan : Bool)
    (stale : Option Row) (changed : List Nat) : Except KeyStop KeyState := do
  let state ← children.foldlM (fun (state : KeyState) (link : ForeignKeyLink) => match link.parent with
    | .located parent key =>
      if link.hasNull row.values then pure state else
      match catalog.tableAt parent with
      | none => throw .undescribed
      | some shape =>
        let extra := if parent == position then staleRows key stale changed else []
        let itself := if parent == position then some row else none
        if parentFound shape key link row.values ((state.database catalog).rowsAt parent ++ extra) itself then pure state
        else pure { state with counter := state.counter + 1 }
    | .missing | .mismatch _ => throw .undescribed) state
  if !scan then return state
  parents.foldlM (fun (state : KeyState) (link : ForeignKeyLink) => match link.parent with
    | .located _ key =>
      if state.counter == 0 then pure state else
      let extra := if link.child == position then stale.toList else []
      pure { state with counter := state.counter - (childRows (state.database catalog) link key position row extra false).length }
    | .mismatch _ | .missing => throw .undescribed) state

end Belay.Sqlite.Model
