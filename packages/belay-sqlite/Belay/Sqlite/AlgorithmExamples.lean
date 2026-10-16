import Belay.Sqlite.UpsertExamples
import Belay.Sqlite.UpsertConforms

set_option doc.verso true

/-! Examples of the conflict algorithms of INSERT (ADR 0012, amendment 4; slice 5d), checked
by {lit}`#guard` and checked against native SQLite 3.51.0, on the table
{lit}`t(k INTEGER UNIQUE, u INTEGER UNIQUE, v NOT NULL)` of
{lit}`Belay.Sqlite.UpsertExamples`, with the rows {lit}`(1, 1, 'a')` and {lit}`(2, 2, 'b')`. -/

namespace Belay.Sqlite.AlgorithmExamples
open Belay.Sqlite UpsertExamples

/-- The policy of {lit}`INSERT OR algorithm`: the algorithm for both keys and every
column. -/
def everywhere (algorithm : ConflictAlgorithm) : Resolved.ConflictPolicy :=
  { keys := [algorithm, algorithm], notNull := [algorithm, algorithm, algorithm] }

/-- The run of {lit}`INSERT OR algorithm` of the rows. -/
def run (algorithm : ConflictAlgorithm) (rows : List (List Value)) :
    Except (ExecutionError × Table × List Row) (Table × List Row) :=
  LiteralData.upsertRun keys (everywhere algorithm) [] table rows

/-- The values of the table of a run: the final table, or the table before the failing
row. -/
def valuesOf (algorithm : ConflictAlgorithm) (rows : List (List Value)) : List (List Value) :=
  (LiteralData.runTable (run algorithm rows)).rows.map (·.values)

/-- The error of a run, or none. -/
def errorOf (algorithm : ConflictAlgorithm) (rows : List (List Value)) : Option ExecutionError :=
  match run algorithm rows with
  | .ok _ => none
  | .error (reason, _, _) => some reason

/-- A new row, a row that conflicts with {lit}`(1, 1, 'a')` on {lit}`k`, and a new row. -/
def mixed : List (List Value) :=
  [[.integer 3, .integer 3, letter 99], [.integer 1, .integer 9, letter 120], [.integer 4, .integer 4, letter 100]]

-- FAIL stops at the conflicting row and keeps the earlier one; ABORT and ROLLBACK fail.
#guard errorOf .fail mixed == some .constraintFail
#guard valuesOf .fail mixed == (table.rows.map (·.values)) ++ [[.integer 3, .integer 3, letter 99]]
#guard errorOf .abort mixed == some .constraintViolation
#guard errorOf .rollback mixed == some .constraintRollback
-- IGNORE skips the conflicting row and the row with a NULL in the NOT NULL column.
#guard errorOf .ignore (mixed ++ [[.integer 5, .integer 5, .null]]) == none
#guard valuesOf .ignore (mixed ++ [[.integer 5, .integer 5, .null]]) == (table.rows.map (·.values)) ++
  [[.integer 3, .integer 3, letter 99], [.integer 4, .integer 4, letter 100]]
-- REPLACE deletes both rows that the new row conflicts with, one on each key.
#guard valuesOf .replace [[.integer 1, .integer 2, letter 114]] == [[.integer 1, .integer 2, letter 114]]
-- REPLACE of a NULL in a NOT NULL column without a default is ABORT.
#guard errorOf .replace [[.integer 7, .integer 7, .null]] == some .constraintViolation
-- A REPLACE key is checked after an ABORT key: the row fails and deletes nothing.
#guard (match LiteralData.upsertRun keys ⟨[.replace, .abort], []⟩ [] table [[.integer 1, .integer 2, letter 120]] with
  | .error (reason, _, _) => some reason
  | .ok _ => none) == some .constraintViolation

end Belay.Sqlite.AlgorithmExamples
