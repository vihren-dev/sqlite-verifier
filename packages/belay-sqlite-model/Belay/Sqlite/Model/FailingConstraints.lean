import Belay.Sqlite.Model.StatementStep
import Belay.Sqlite.Model.WriteFailure
import Belay.Sqlite.Model.UpdateFailure

set_option doc.verso true

/-! The constraints that SQLite may name when a statement fails with a constraint error. The
errors of the model carry no constraint, so {lit}`failingConstraints` computes it again from the
statement and the database, along the same computation as
{name}`Belay.Sqlite.Model.runStatement`. For a write that can fire no trigger and checks no
foreign key, two theorems show that it names a constraint exactly when the statement fails with a
constraint error. -/

namespace Belay.Sqlite.Model

/-- Whether the error is a constraint error, SQLite's result code {lit}`SQLITE_CONSTRAINT`:
{name}`ExecutionError.constraintViolation`, {name}`ExecutionError.constraintFail` or
{name}`ExecutionError.constraintRollback`. A CHECK constraint that fails on the default of ADD
COLUMN is {name}`ExecutionError.checkColumnDefault`, which has the code {lit}`SQLITE_ERROR`. -/
def ExecutionError.isConstraint : ExecutionError → Bool
  | .constraintViolation | .constraintFail | .constraintRollback => true
  | .unmodeled | .prepare _ | .transactionAlreadyActive | .noActiveTransaction | .integerOverflow
  | .datatypeMismatch | .functionError | .nullColumnDefault | .nonConstantColumnDefault | .checkColumnDefault => false

/-- The rules that a write runs row by row ({name}`Resolved.WriteRules`), as the statement
keeps them; none for a statement that is not an INSERT, UPDATE, DELETE or DROP. Resolution
({name}`ResolveState.withWrite`) sets them exactly when the write has a foreign key to check
(foreign keys are on and the table has a key that the write must check) or a trigger that it can
fire, also one whose WHEN is always false. So for a resolved statement, none means that the write
can fire no trigger and checks no foreign key. A statement built by hand with none counts as
plain whatever triggers the catalog has. -/
def Resolved.Statement.writeRules : Resolved.Statement → Option Resolved.WriteRules
  | .insert _ _ _ _ rules | .upsert _ _ _ _ _ _ rules | .update _ _ _ _ _ rules | .delete _ _ _ _ rules
  | .drop _ rules => rules
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .begin | .commit | .rollback
  | .prepareError _ | .query .. | .setting .. => none

/-- The constraints that SQLite may name when the statement fails on the database at the clock
value with the counters and the values bound to its parameters ({name}`runStatement`). A statement that does not fail with a constraint error
({name}`ExecutionError.isConstraint`) gives none. Otherwise:

* a plain INSERT: {name}`LiteralData.insertFailure`;
* an INSERT with clauses or algorithms: {name}`LiteralData.upsertRowFailure` of the row at which
  it stops;
* an UPDATE: {name}`Catalog.updateReport`;
* {lit}`CREATE UNIQUE INDEX`: the index;
* a write that can fire a trigger or that checks a foreign key
  ({name}`Resolved.Statement.writeRules` is some), and every other statement: none. -/
def failingConstraints (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    ConstraintReport :=
  match (runStatement clock counters parameters statement database).effect with
  | .ok _ => { candidates := [] }
  | .error (reason, _) => if !reason.isConstraint then { candidates := [] } else
  let ofTable (target : Nat) (failure : Option TableFailure) : List ConstraintFailure :=
    (failure.map (database.catalog.candidates target)).getD []
  match statement with
  | .insert target rows _ subqueries none => match database.table target with
    | none => { candidates := [] }
    | some table =>
      let values := Resolved.rowsAt (Resolved.statementContext clock counters parameters database subqueries) table.shape.columns rows
      { candidates := ofTable target (LiteralData.insertFailure (database.keys target table) table values) }
  | .upsert target rows clauses _ algorithm subqueries none => match database.table target with
    | none => { candidates := [] }
    | some table =>
      let context := Resolved.statementContext clock counters parameters database subqueries
      let keys := database.keys target table
      let policy := database.catalog.writePolicy target table.shape algorithm
      match (LiteralData.upsertSteps context keys policy clauses table
          (Resolved.rowsAt context table.shape.columns rows)).getLast? with
      | some step =>
        { candidates := ofTable target (LiteralData.upsertRowFailure context keys policy clauses step.before step.values) }
      | none => { candidates := [] }
  | .update target assignments filter _ subqueries none => match database.table target with
    | none => { candidates := [] }
    | some table =>
      let context := Resolved.statementContext clock counters parameters database subqueries
      database.catalog.updateReport target (database.keys target table) (assignments.map (·.1))
        (LiteralData.selectedPositions context filter table) table
        (LiteralData.updated context table assignments filter)
  | .createIndex _ name index => { candidates := [.uniqueIndex name index] }
  | .insert _ _ _ _ (some _) | .upsert _ _ _ _ _ _ (some _) | .update _ _ _ _ _ (some _) | .delete .. | .drop ..
  | .createTable .. | .createTrigger .. | .addColumn .. | .begin | .commit | .rollback | .prepareError _ | .query ..
  | .setting .. => { candidates := [] }

/-- For every table position and optional failure that is some: the candidates of the failure
({name}`Catalog.candidates`), or none for no failure, are not empty. Proof sketch: the failure is
some, so the candidates are those of {name}`Catalog.candidates_ne_nil`. -/
theorem candidates_getD_ne_nil {catalog : Catalog} {target : Nat} {failure : Option TableFailure}
    (found : failure.isSome) : (failure.map (catalog.candidates target)).getD [] ≠ [] := by
  cases failure with
  | none => simp at found
  | some failure => simpa using Catalog.candidates_ne_nil catalog target failure

end Belay.Sqlite.Model
