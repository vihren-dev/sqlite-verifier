import Belay.Sqlite.Model.Output
import Belay.Sqlite.Model.Resolution.Messages
import Belay.Sqlite.Model.FailingConstraintLaws

set_option doc.verso true

/-! The message of a statement that fails while it runs, as an elaboration error shows it. Where
the model keeps what SQLite's message says, the text is SQLite 3.51's, measured with the
{lit}`sqlite3` shell. A constraint failure names the constraint
({name}`Belay.Sqlite.Model.failingConstraints`), except in a write that can fire a trigger or
that checks foreign keys. A failed function has no such text, because the errors of the model do not keep
SQLite's message. -/

namespace Belay.Sqlite.Model

/-- The message for a constraint failure under ABORT, FAIL or ROLLBACK in a write that can fire
a trigger (also one whose WHEN is always false) or that checks foreign keys. It starts with SQLite's text for the result code
{lit}`SQLITE_CONSTRAINT` ({lit}`sqlite3_errstr`). SQLite's message for the statement also names
the constraint, for example {lit}`FOREIGN KEY constraint failed`; the model does not find the
constraint for such a write, so this text says so, and tells the user where to see SQLite's
message. This is the only place that gives the text. -/
def triggerOrKeyConstraintMessage : String :=
  "constraint failed; the model does not name the constraint that fails in a write that can fire " ++
    "a trigger or that checks foreign keys. Run the statement in the sqlite3 shell to see SQLite's message"

/-- The message for a constraint failure of the statement on the database at the clock value
with the counters and the values bound to its parameters:
{name}`triggerOrKeyConstraintMessage` for a write that can fire a trigger or that checks foreign
keys ({name}`Resolved.Statement.writeRules` is some), and otherwise SQLite's message for the
constraints of {name}`failingConstraints` ({name}`ConstraintReport.message`). -/
def constraintMessage (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    String :=
  match statement.writeRules with
  | some _ => triggerOrKeyConstraintMessage
  | none => (failingConstraints clock counters parameters statement database).message database.catalog

/-- The message for a function that fails while the statement runs, such as a JSON function
with malformed JSON. -/
def functionFailedMessage : String :=
  "a function of the statement failed, for example on malformed JSON; the model does not keep " ++
    "SQLite's message for it. Run the statement in the sqlite3 shell to see that message"

/-- The message of the error of the statement on the database at the clock value, with the counters and the
values bound to its parameters, as SQLite
3.51 gives it where the model keeps what the message says:

* {name}`ExecutionError.prepare` gives SQLite's message of the prepare error
  ({name}`PrepareError.message`);
* {name}`ExecutionError.noActiveTransaction` gives SQLite's text for ROLLBACK, and for every
  other statement its text for COMMIT and END;
* a constraint failure gives {name}`constraintMessage`, which names the constraint except in a
  write that can fire a trigger or that checks foreign keys;
* {name}`ExecutionError.functionError` gives {name}`functionFailedMessage`, which is not
  SQLite's;
* {name}`ExecutionError.unmodeled` gives {name}`unmodeledHere`; a run ends at such a statement,
  so a failure of a run does not have it.

For example, {assert}`ExecutionError.integerOverflow.message 0 {} [] .commit {} = "integer overflow"`. -/
def ExecutionError.message (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    (database : Database) :
    ExecutionError → String
  | .unmodeled => unmodeledHere
  | .prepare error => error.message
  | .transactionAlreadyActive => "cannot start a transaction within a transaction"
  | .noActiveTransaction => match statement with
    | .rollback => "cannot rollback - no transaction is active"
    | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .begin | .commit
    | .insert .. | .upsert .. | .update .. | .delete .. | .prepareError _ | .query .. | .setting .. =>
      "cannot commit - no transaction is active"
  | .constraintViolation | .constraintFail | .constraintRollback => constraintMessage clock counters parameters statement database
  | .integerOverflow => "integer overflow"
  | .datatypeMismatch => "datatype mismatch"
  | .functionError => functionFailedMessage
  | .nullColumnDefault => "Cannot add a NOT NULL column with default value NULL"
  | .nonConstantColumnDefault => "Cannot add a column with non-constant default"
  | .checkColumnDefault => "CHECK constraint failed"

end Belay.Sqlite.Model
