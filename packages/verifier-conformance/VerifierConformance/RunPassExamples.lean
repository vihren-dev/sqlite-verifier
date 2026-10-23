import VerifierConformance.Classify
import Belay.Sqlite.Model.ScriptRunExamples

set_option doc.verso true

/-! Examples of the classification pass of the run that continues after an error
({name}`Belay.Sqlite.Model.Conformance.runPassFrom`), checked by the kernel when the package
builds. They check what the comparison with a recorder that runs on reads after a failed
statement: the transaction status, the primary code and the phase after each statement, and the
outputs of later statements, for an error inside a transaction, {lit}`OR ROLLBACK` inside a
transaction, and a failed {lit}`ADD COLUMN`. -/

namespace Belay.Sqlite.Model.Conformance.RunPassExamples

open Belay.Sqlite.Model Syntax Resolution.Examples ScriptRunExamples

/-- The pass of the statements from the empty database, with the default profile, without a
clock and without bound values. -/
def passOf (script : List Syntax.Statement) : RunPass :=
  runPassFrom { profile := defaults, mode := .execution } none 0 { state := { database := {} } }
    (bindValues script [])

/-- The transaction status, the primary code and the phase of the error after each statement
of a pass. -/
def statusOf (pass : RunPass) : List (Bool × Nat × Option ErrorPhase) :=
  pass.observations.map fun observation =>
    (observation.transactionOpen, primaryCode observation.error, errorPhase observation.error)

/-- The output of a query of the column {lit}`name` that gives the rows. -/
def namesOutput (rows : List ResultRow) : Option StatementOutput :=
  some { columns := ["name"], rows, changes := none }

/-- The statements of the first two examples: a table, {lit}`BEGIN`, a row, an INSERT of the
same key with the algorithm, {lit}`COMMIT` and a query of the names. -/
def failedInsert (algorithm : Option ConflictAlgorithm) : List Syntax.Statement :=
  [createT, .begin, insertT "1" "a", insertT "1" "b" algorithm, .commit, selectNames]

-- A constraint failure under ABORT inside a transaction fails at step and keeps the transaction
-- open; COMMIT then closes it, and the query gives the first row.
example : statusOf (passOf (failedInsert none)) =
    [(false, 0, none), (true, 0, none), (true, 0, none), (true, 19, some .step), (false, 0, none),
      (false, 0, none)] := by
  decide +kernel
example : (passOf (failedInsert none)).outputs.getLast? = some (namesOutput [[textValue "a"]]) := by
  decide +kernel

-- OR ROLLBACK rolls back and closes the transaction: COMMIT then fails at step with code 1, and
-- the query gives no row.
example : statusOf (passOf (failedInsert (some .rollback))) =
    [(false, 0, none), (true, 0, none), (true, 0, none), (false, 19, some .step), (false, 1, some .step),
      (false, 0, none)] := by
  decide +kernel
example : (passOf (failedInsert (some .rollback))).outputs.getLast? = some (namesOutput []) := by
  decide +kernel

/-- {lit}`SELECT c FROM t`. -/
def selectAdded : Syntax.Statement :=
  .select [.expression (.identifier (name! "c") .none) none ""] (some { table := name! "t", alias := none })
    [] none [] [] none none

/-- {lit}`ALTER TABLE t ADD COLUMN c` with the constraints. -/
def addColumnC (constraints : List ColumnConstraint) : Syntax.Statement :=
  .addColumn (name! "t") { name := name! "c", declaredType := some "INTEGER", constraints }

-- A failed ADD COLUMN NOT NULL leaves no column: the query of the column fails at prepare. A
-- later ADD COLUMN with a default succeeds, and the query then gives the default.
example : statusOf (passOf [createT, insertT "1" "a", addColumnC [.notNull], selectAdded,
      addColumnC [.default (.numeric "2") "2"], selectAdded]) =
    [(false, 0, none), (false, 0, none), (false, 1, some .step), (false, 1, some .prepare), (false, 0, none),
      (false, 0, none)] := by
  decide +kernel
example : (passOf [createT, insertT "1" "a", addColumnC [.notNull], selectAdded,
      addColumnC [.default (.numeric "2") "2"], selectAdded]).outputs.getLast? =
    some (some { columns := ["c"], rows := [[.integer 2]], changes := none }) := by
  decide +kernel

-- A run that ends at a statement ends the pass: it is not supported, and its last result is
-- the reason.
example : (passOf [createT, selectOf (.currentTime "CURRENT_TIMESTAMP"), selectNames]).supported = false := by
  decide +kernel
example : (passOf [createT, selectOf (.currentTime "CURRENT_TIMESTAMP"), selectNames]).results =
    [.done 0, .unmodeled clockUnmodeled] := by
  decide +kernel

end Belay.Sqlite.Model.Conformance.RunPassExamples
