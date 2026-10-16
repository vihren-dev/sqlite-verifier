import Belay.Sqlite.Upsert

set_option doc.verso true

/-! The rows of an INSERT with {lit}`ON CONFLICT` clauses or conflict algorithms (ADR 0012,
amendment 4, slices 5c and 5d), checked on native SQLite 3.51.0. The rows are processed
one at a time, in order, so a later row sees the rows that earlier ones wrote. For each
row:

* a rowid alias that is no integer is {lit}`datatype mismatch`, which is ABORT under
  every algorithm;
* a NULL in a NOT NULL column fails with the algorithm of that column, before any
  conflict handling;
* the first clause whose target key has a conflicting row handles the row;
* otherwise a conflict on a key whose algorithm is not REPLACE fails with that
  algorithm; then every row that conflicts on a REPLACE key is deleted, and the row is
  inserted.

A failure with IGNORE skips the row; FAIL and ROLLBACK have their own errors
({lit}`ExecutionError.constraintFail`, {lit}`ExecutionError.constraintRollback`); every
other failure is ABORT. -/

namespace Belay.Sqlite
namespace LiteralData

/-- The algorithm at a position of a policy list, ABORT for a position without an
entry. -/
def algorithmAt (algorithms : List ConflictAlgorithm) (position : Nat) : ConflictAlgorithm :=
  algorithms.getD position .abort

/-- The error of a constraint failure with an algorithm: FAIL and ROLLBACK have their
own errors, and every other algorithm fails as ABORT. -/
def failureError : ConflictAlgorithm → ExecutionError
  | .fail => .constraintFail
  | .rollback => .constraintRollback
  | .abort | .ignore | .replace => .constraintViolation

/-- A failed constraint of a row with its algorithm: IGNORE skips the row and keeps the
table; every other algorithm is the error of {name}`failureError`. A NULL in a NOT NULL
column with REPLACE is ABORT, as the model admits no default that REPLACE could use. -/
def failedConstraint (table : Table) : ConflictAlgorithm → Except ExecutionError (Table × Option Row)
  | .ignore => .ok (table, none)
  | .rollback => .error (failureError .rollback)
  | .abort => .error (failureError .abort)
  | .fail => .error (failureError .fail)
  | .replace => .error (failureError .replace)

/-- The first column position, in table order, with NOT NULL and a NULL cell; none
when every NOT NULL cell is set. -/
def nullColumn (columns : List CatalogColumn) (values : List Value) : Option Nat :=
  (columns.zip values).findIdx? fun (column, value) => column.notNull && value == .null

/-- Whether the proposed row conflicts with a row of the table on the key at the
position. -/
def conflictsAt (keys : List (List Nat)) (table : Table) (proposed : Row) (index : Nat) : Bool :=
  (keys[index]?).any fun key => table.rows.any fun row => keyEqual key row proposed

/-- The first key position, in order, whose algorithm is not REPLACE and on which the
proposed row conflicts; SQLite checks the REPLACE keys after the others. -/
def blockingKey (keys : List (List Nat)) (algorithms : List ConflictAlgorithm) (table : Table)
    (proposed : Row) : Option Nat :=
  (List.range keys.length).find? fun index =>
    algorithmAt algorithms index != .replace && conflictsAt keys table proposed index

/-- The table without the rows that conflict with the proposed row on a key whose
algorithm is REPLACE. -/
def replaced (keys : List (List Nat)) (algorithms : List ConflictAlgorithm) (table : Table) (proposed : Row) :
    Table :=
  { table with rows := table.rows.filter fun row => !((List.range keys.length).any fun index =>
      algorithmAt algorithms index == .replace && (keys[index]?).any fun key => keyEqual key row proposed) }

/-- Insert the proposed row without a handling clause: a conflict on a key that is not
REPLACE fails with its algorithm ({name}`failedConstraint`); otherwise the rows that
conflict on REPLACE keys are deleted ({name}`replaced`), the row is appended with the
rowid that it had before the deletion, and {name}`checkedRow` checks the table. -/
def insertChecked (keys : List (List Nat)) (algorithms : List ConflictAlgorithm) (table : Table) (proposed : Row) :
    Except ExecutionError (Table × Option Row) :=
  match blockingKey keys algorithms table proposed with
  | some index => failedConstraint table (algorithmAt algorithms index)
  | none =>
    let kept := replaced keys algorithms table proposed
    checkedRow keys { kept with rows := kept.rows ++ [proposed] } proposed

/-- One row of an INSERT with clauses or algorithms: the table after it and the row that
it inserted or updated, none for a skipped row; or the error of the statement. -/
def upsertRow (keys : List (List Nat)) (policy : Resolved.ConflictPolicy) (clauses : List Resolved.ConflictClause)
    (table : Table) (values : List Value) : Except ExecutionError (Table × Option Row) :=
  if aliasMismatch table.shape values then .error .datatypeMismatch else
  let proposed := proposedRow table values
  match nullColumn table.shape.columns proposed.values with
  | some column => failedConstraint table (algorithmAt policy.notNull column)
  | none => match handlingClause keys clauses table proposed with
    | none => insertChecked keys policy.keys table proposed
    | some (clause, existing) => match clause.action with
      | .nothing => .ok (table, none)
      | .update assignments filter => updateExisting keys table assignments filter existing proposed

/-- The rows in order ({name}`upsertRow`): the final table and the inserted and updated
rows in row order; or the first error with the table before its row and the rows
written before it, which a FAIL failure keeps. -/
def upsertRun (keys : List (List Nat)) (policy : Resolved.ConflictPolicy) (clauses : List Resolved.ConflictClause)
    (table : Table) : List (List Value) → Except (ExecutionError × Table × List Row) (Table × List Row)
  | [] => .ok (table, [])
  | values :: rest => match upsertRow keys policy clauses table values with
    | .error reason => .error (reason, table, [])
    | .ok (next, written) => match upsertRun keys policy clauses next rest with
      | .error (reason, reached, later) => .error (reason, reached, written.toList ++ later)
      | .ok (final, later) => .ok (final, written.toList ++ later)

/-- Whether every reached row has a bounded proposed rowid, and every table after a row
has bounded rowids. SQLite chooses a random rowid after the largest one, which the model
does not describe. -/
def upsertBounded (keys : List (List Nat)) (policy : Resolved.ConflictPolicy)
    (clauses : List Resolved.ConflictClause) (table : Table) : List (List Value) → Bool
  | [] => true
  | values :: rest => boundedInteger (newRowid table values) &&
    match upsertRow keys policy clauses table values with
    | .error _ => true
    | .ok (next, _) => next.rows.all (fun row => boundedInteger row.rowid) && upsertBounded keys policy clauses next rest

/-- Require {name}`tableReady` before the write, {name}`aliasReady`, one stored value per
column in each row, a column at every position that a {lit}`DO UPDATE` assigns, and
{name}`upsertBounded`. This check does not establish the constraints of the result,
which {name}`checkedRow` checks. -/
def upsertReady (keys : List (List Nat)) (policy : Resolved.ConflictPolicy) (table : Table)
    (clauses : List Resolved.ConflictClause) (rows : List (List Value)) : Bool :=
  tableReady keys table && aliasReady table.shape &&
  rows.all (fun values => values.length == table.shape.columns.length &&
    (table.shape.columns.zip values).all (fun (column, value) => storedForm column.affinity value)) &&
  clauses.all (fun clause => match clause.action with
    | .nothing => true
    | .update assignments _ => assignments.all fun (position, _) => (table.shape.columns[position]?).isSome) &&
  upsertBounded keys policy clauses table rows

/-- The database after a failed INSERT with clauses or algorithms: with the table before
the failing row at the position for a FAIL failure, which keeps the earlier rows; the
input database for every other failure. -/
def failedDatabase (database : Database) (at_ : Nat) (reason : ExecutionError) (reached : Table) : Database :=
  match reason with
  | .constraintFail => database.set at_ reached
  | .unmodeled | .prepare _ | .transactionAlreadyActive | .noActiveTransaction | .constraintViolation
  | .constraintRollback | .integerOverflow | .datatypeMismatch => database

end LiteralData
end Belay.Sqlite
