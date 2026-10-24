import Belay.Sqlite.SqlDiagnostics
import Belay.Sqlite.Model

set_option doc.verso true

/-! The errors that {lit}`db! r"..."` shows in the SQL text, as byte ranges of the text. The text
runs on the empty database statement by statement, as {lit}`Database.Raw.run` runs it: a
statement that fails shows at the statement, a prepare error at its name, and the statement that
ends the run at the node of its restriction or at the statement. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model Translation

/-- The message of a statement whose output has the result code but for which
{name}`runScriptStepFailure` gives no error. {name}`runScriptStep_error_failure` proves that
this does not occur; the text is there so that the match has a message for every case. -/
def missingFailureMessage (code : Nat) : String :=
  s!"the model gives the statement SQLite's result code {code} but no error for it. This is a " ++
    "defect of the model; report the SQL text to the maintainers of the model"

/-- What the user can do after the error of the statement, appended to SQLite's message. A
failed {lit}`CREATE UNIQUE INDEX` writes no row, so its text names the rows of the table and the
index. The texts of a function failure, and of a constraint failure in a write that can fire a
trigger or that checks foreign keys ({name}`triggerOrKeyConstraintMessage`), say it already. -/
def failureAction (statement : Resolved.Statement) : ExecutionError → String
  | .transactionAlreadyActive | .noActiveTransaction =>
    "; remove the statement, or add the BEGIN or COMMIT that it needs"
  | .integerOverflow | .datatypeMismatch | .nullColumnDefault | .nonConstantColumnDefault
  | .checkColumnDefault | .unmodeled | .prepare _ =>
    "; correct the statement, or the statements before it that give the data that it reads"
  | .constraintViolation | .constraintFail | .constraintRollback => match statement with
    | .createIndex .. => "; remove the rows whose values of the index are equal, or change the index"
    | .insert .. | .upsert .. | .update .. | .delete .. | .drop .. | .createTable .. | .createTrigger ..
    | .addColumn .. | .begin | .commit | .rollback | .prepareError _ | .query .. | .setting .. =>
      match statement.writeRules with
      | some _ => ""
      | none => "; correct the row, or the statement that writes it"
  | .functionError => ""

/-- The error of a statement of a text, which binds no values, whose output is
{name}`Output.error` with the code: a prepare
error at its name ({name}`prepareDiagnostic`), and every other error with its message
({name}`ExecutionError.message` at the clock value 0, which a statement that runs without a
clock has, with the counters that the statement reads, on the database of the connection, then {name}`failureAction`) at the statement. The
error comes from {name}`runScriptStepFailure` without a clock, which runs the statement on the
same clock value and database
and gives an error of that code for each such output ({name}`runScriptStep_error_failure`); when
it gives none, the message is {name}`missingFailureMessage`. -/
def failureDiagnostic (bytes : ByteArray) (index : Nat) (connection : Connection)
    (item : Located Syntax.Statement) (code : Nat) : Diagnostic :=
  let (start, stop) := statementRange item
  let database := connection.state.database
  match runScriptStepFailure runContext none index connection item.value [] with
  | some (_, .prepare error) => prepareDiagnostic bytes item error
  | some (statement, failure@.unmodeled) | some (statement, failure@.transactionAlreadyActive)
  | some (statement, failure@.noActiveTransaction) | some (statement, failure@.constraintViolation)
  | some (statement, failure@.constraintFail) | some (statement, failure@.constraintRollback)
  | some (statement, failure@.integerOverflow) | some (statement, failure@.datatypeMismatch)
  | some (statement, failure@.functionError) | some (statement, failure@.nullColumnDefault)
  | some (statement, failure@.nonConstantColumnDefault) | some (statement, failure@.checkColumnDefault) =>
    { start, stop, message := failure.message 0 (connection.state.counters.view statement.counterReads) [] statement database ++ failureAction statement failure }
  | none => { start, stop, message := missingFailureMessage code }

/-- The errors of a statement with its output: {name}`failureDiagnostic` for
{name}`Output.error`, and none for every other output. -/
def outputDiagnostics (bytes : ByteArray) (index : Nat) (connection : Connection)
    (item : Located Syntax.Statement) : Output → List Diagnostic
  | .error code => [failureDiagnostic bytes index connection item code]
  | .rows _ | .done _ | .oneOf _ | .unmodeled _ => []

/-- The error of the statement that ends the run, with the reason of the run: when the
statement resolves to a restriction against the connection, the restriction at its node
({name}`restrictionDiagnostic`); otherwise the reason at the statement, for example
{name}`clockUnmodeled` for a statement that reads the clock. -/
def endedDiagnostic (connection : Connection) (item : Located Syntax.Statement) (reason : String) :
    Diagnostic :=
  match resolveStatement runContext connection.resolveState item.value with
  | .error restriction => restrictionDiagnostic item restriction
  | .ok _ => let (start, stop) := statementRange item; { start, stop, message := reason }

/-- The message of a text that leaves a transaction open at its end. -/
def openTransactionMessage : String :=
  "the text of db! leaves a transaction open at its end; end the transaction with COMMIT, " ++
    "or remove its BEGIN"

/-- The error of a run that reaches the end of a text of {lit}`size` bytes with a transaction
open: at the end of the text. A run that ends early at a statement does not give it, because
the statements after that statement do not run, and one of them can end the transaction, as in
{lit}`BEGIN; SELECT CURRENT_TIMESTAMP; COMMIT`. -/
def endDiagnostics (size : Nat) (connection : Connection) : List Diagnostic :=
  match connection.state.snapshot with
  | some _ => [{ start := size, stop := size, message := openTransactionMessage }]
  | none => []

/-- Run the statements of a text in order from a zero-based index on the connection, each with
{name}`runScriptStep`, no values, no clock and the surface's context, and give the errors and the connection at the
end. Each statement that fails gives its error ({name}`outputDiagnostics`), and the run goes on.
A statement that ends the run gives {name}`endedDiagnostic`, and the statements after it give
no error. A run that reaches the end of the text with an open transaction gives
{name}`endDiagnostics`; a run that ends early does not, because the statements that do not run
can end the transaction. -/
def runDiagnosticsFrom (bytes : ByteArray) (index : Nat) (connection : Connection) :
    List (Located Syntax.Statement) → List Diagnostic × Connection
  | [] => (endDiagnostics bytes.size connection, connection)
  | item :: rest => match runScriptStep runContext none index connection item.value [] with
    | .ended reason => ([endedDiagnostic connection item reason], connection)
    | .continued output next =>
      let later := runDiagnosticsFrom bytes (index + 1) next rest
      (outputDiagnostics bytes index connection item output ++ later.1, later.2)

/-- For every text, index, connection and list of statements: the connection at the end of
{name}`runDiagnosticsFrom` is the connection at the end of {name}`runScriptFrom` over the same
statements, each with no values, without a clock, with the surface's context. So the errors come from the model's run, and not from a
second definition of it. Proof sketch: induction on the statements; both functions take the
same step for each statement. -/
theorem runDiagnosticsFrom_connection (bytes : ByteArray) :
    ∀ (index : Nat) (connection : Connection) (items : List (Located Syntax.Statement)),
      (runDiagnosticsFrom bytes index connection items).2 =
        (runScriptFrom runContext none index connection (items.map fun item => (item.value, []))).connection
  | _, _, [] => rfl
  | index, connection, item :: rest => by
    simp only [runDiagnosticsFrom, runScriptFrom, List.map]
    cases runScriptStep runContext none index connection item.value [] with
    | ended reason => rfl
    | continued output next => exact runDiagnosticsFrom_connection bytes (index + 1) next rest

/-- The errors of the statements of a {lit}`db!` text, run on the empty database
({name}`runDiagnosticsFrom` from index 0), and the connection at the end. -/
def runDiagnostics (bytes : ByteArray) (items : List (Located Syntax.Statement)) : List Diagnostic × Connection :=
  runDiagnosticsFrom bytes 0 Database.empty.raw.connection items

/-- For every text and list of statements: the connection at the end of
{name}`runDiagnostics` is the connection at the end of {name}`Database.Raw.run` of the script
of the statements, each with no values, on the empty database. Proof sketch: {name}`runDiagnosticsFrom_connection`
from index 0. -/
theorem runDiagnostics_connection (bytes : ByteArray) (items : List (Located Syntax.Statement)) :
    (runDiagnostics bytes items).2 = (Database.Raw.run {} ⟨items.map fun item => (item.value, [])⟩).connection :=
  runDiagnosticsFrom_connection bytes 0 _ items

end Belay.Sqlite
