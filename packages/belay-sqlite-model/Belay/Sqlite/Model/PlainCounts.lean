import Belay.Sqlite.Model.Counters
import Belay.Sqlite.Model.StatementRun
import Belay.Sqlite.Model.UpsertRun

set_option doc.verso true

/-! What a write without foreign-key checks and without trigger programs does to the counters of
its connection (ADR 0024, D2, checked natively with 3.51.0): the counts of a plain INSERT, an
INSERT with {lit}`ON CONFLICT` clauses or algorithms, an UPDATE and a DELETE, from the same
computation that gives their effect. A write that checks foreign keys or runs programs has the
counts of its row engine ({name}`Belay.Sqlite.Model.KeyRun`). -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- The rowid that {lit}`last_insert_rowid()` takes after a statement inserted the rows into a
table: the rowid of the last of them, and none for a table {lit}`WITHOUT ROWID` or when no row
was inserted, because the statement then leaves the value. -/
def lastInsertedRowid (shape : CatalogTable) (inserted : List Row) : Option Int :=
  if shape.withoutRowid then none else inserted.getLast?.map (·.rowid)

/-- Whether the first rows of an INSERT can be in the table together: the table with them keeps
the constraints of its keys and has distinct rowids, as {name}`checkedWrite` checks. -/
def prefixHolds (keys : List UniqueKey) (table : Table) (rows : List (List Value)) : Bool :=
  let result := inserted table rows
  constraints keys result && rowidsDistinct result

/-- The number of rows that a plain INSERT stores before it stops. SQLite checks each row before
it inserts it, so the rows are the longest first part of the rows that {name}`prefixHolds` accepts,
up to the first row with a rowid alias that is no integer ({name}`aliasMismatch`). A prefix that
holds makes every shorter prefix hold, so the count is the number of prefixes that hold. -/
def insertedBefore (keys : List UniqueKey) (table : Table) (rows : List (List Value)) : Nat :=
  let limit := (rows.findIdx? (aliasMismatch table.shape)).getD rows.length
  ((List.range limit).filter fun index => prefixHolds keys table (rows.take (index + 1))).length

/-- The counts of a plain INSERT of the rows (ADR 0024, D2). A success changes one row for each
row, and sets {lit}`last_insert_rowid()` to the rowid of the last. A failure of the statement
changes no row, and sets {lit}`last_insert_rowid()` to the rowid of the last row that the
statement stored before the failing row ({name}`insertedBefore`), which the rollback of the
statement does not take back. -/
def insertCounts (effect : Effect) (keys : List UniqueKey) (table : Table) (rows : List (List Value)) : Counts :=
  let stored (count : Nat) : Option Int :=
    if count = 0 then none else lastInsertedRowid table.shape ((inserted table (rows.take count)).rows.drop table.rows.length)
  match effect with
  | .ok _ => { changes := some rows.length, total := rows.length, lastRowid := stored rows.length }
  | .error _ => { changes := some 0, lastRowid := stored (insertedBefore keys table rows) }

/-- The rows that the reached rows of an INSERT with clauses or algorithms wrote, in order: the
rows that they inserted or updated. -/
def upsertWritten (steps : List UpsertStep) : List Row :=
  steps.flatMap fun step => match step.result with
    | .ok (_, written) => written.toList
    | .error _ => []

/-- The rows that the reached rows of an INSERT with clauses or algorithms inserted, in order:
the written rows that no clause handled. A {lit}`DO UPDATE` row does not set
{lit}`last_insert_rowid()`. -/
def upsertInserted (keys : List UniqueKey) (clauses : List Resolved.ConflictClause) (steps : List UpsertStep) :
    List Row :=
  steps.flatMap fun step => match step.result with
    | .ok (_, some written) =>
      if (handlingClause keys clauses step.before (proposedRow step.before step.values)).isNone then [written] else []
    | .ok (_, none) | .error _ => []

/-- The counts of an INSERT with clauses or algorithms (ADR 0024, D2): it changes each row that it
inserted or updated; a FAIL failure keeps the rows before the failing row, and every other
failure keeps none. {lit}`last_insert_rowid()` takes the rowid of the last inserted row, also
when the statement fails later. -/
def upsertCounts (keys : List UniqueKey) (clauses : List Resolved.ConflictClause) (shape : CatalogTable)
    (steps : List UpsertStep) (failure : Option ExecutionError) : Counts :=
  let kept := if failure.any (· ≠ .constraintFail) then 0 else (upsertWritten steps).length
  { changes := some kept, total := kept, lastRowid := lastInsertedRowid shape (upsertInserted keys clauses steps) }

/-- The counts of an UPDATE or a DELETE that changed the rows ({lit}`changed`, the number of rows
that its filter selects) when it succeeds: it changes each of them. A failure changes none. -/
def changedCounts (effect : Effect) (changed : Nat) : Counts :=
  match effect with
  | .ok _ => { changes := some changed, total := changed }
  | .error _ => { changes := some 0 }

end LiteralData
end Belay.Sqlite.Model
