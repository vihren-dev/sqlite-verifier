import Belay.Sqlite.Model.PossibleOutput

set_option doc.verso true

/-! What one statement of a run gives (ADR 0017, D3): its rows, its number of changes, its
error code, every result that SQLite may give for it, or the reason why the model does not
describe it. The run of {lit}`ScriptRun.lean` gives one output for each
statement that it runs. -/

namespace Belay.Sqlite.Model

/-- The output of one statement. For example, an UPDATE that changes one row gives
{lean}`Output.done 1`, and a query with one row of one integer gives
{lean}`Output.rows [[.integer 1]]`. -/
inductive Output where
  /-- A statement that returns rows: a query, or a write with {lit}`RETURNING`. Without an
  order that SQLite promises, the rows are in the normal form ({name}`Resolved.normalForm`). -/
  | rows (rows : List (List Value))
  /-- A statement that returns no rows, with the number of rows that it changed: 0 for a
  statement that is not INSERT, UPDATE or DELETE. -/
  | done (changes : Nat)
  /-- A statement that failed, with SQLite's primary result code
  ({name}`ExecutionError.primaryCode`). -/
  | error (code : Nat)
  /-- A query whose rows depend on an order that SQLite does not promise, with one entry for
  each result that SQLite may give, in a fixed order ({lit}`compareResults`). -/
  | oneOf (results : List (List (List Value)))
  /-- A statement that the model does not describe, with the reason. A run stops at it. -/
  | unmodeled (reason : String)
  deriving DecidableEq

/-- Whether the output ends a run: only {name}`Output.unmodeled` does. -/
def Output.endsRun : Output → Bool
  | .unmodeled _ => true
  | .rows _ | .done _ | .error _ | .oneOf _ => false

/-- Whether the output is a statement's error: only {name}`Output.error` is. -/
def Output.isError : Output → Bool
  | .error _ => true
  | .rows _ | .done _ | .oneOf _ | .unmodeled _ => false

/-- The reason of a statement whose run the model does not describe on the database: its
support check fails, or it writes to a position without a table. -/
def unmodeledHere : String :=
  "the model does not describe what SQLite does for this statement on this database"

/-- The order of two results of a query: row by row by {name}`Resolved.compareRows`, a result
with fewer rows first when its rows begin the other. -/
def compareResults : List (List Value) → List (List Value) → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | first :: rest, other :: others => (Resolved.compareRows first other).then (compareResults rest others)

/-- The output of a query from the results that SQLite may give for it: one result as
{name}`Output.rows`, more than one different result as {name}`Output.oneOf`, each result
once, sorted by {name}`compareResults`, so that the output does not depend on the order in
which the model finds the results. -/
def Output.ofResults (results : List (List (List Value))) : Output :=
  match Resolved.stableSort (fun a b => (compareResults a b).isLE) results.eraseDups with
  | [result] => .rows result
  | [] => .unmodeled "the model gives no result for this query"
  | first :: second :: rest => .oneOf (first :: second :: rest)

/-- Whether a write statement returns rows: a write with {lit}`RETURNING` expressions. -/
def Resolved.Statement.returnsRows : Resolved.Statement → Bool
  | .insert _ _ returning .. | .upsert _ _ _ returning .. | .update _ _ _ returning .. | .delete _ _ returning .. =>
    !returning.isEmpty
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .begin | .commit | .rollback
  | .prepareError _ | .query .. | .setting .. => false

/-- The output of a statement from its transition and from what the model computes for it with
the values bound to its parameters
({name}`statementOutput`, {name}`possibleOutput`):

* a statement that stops with an error gives {name}`Output.error` of its primary result code,
  except {lean}`ExecutionError.unmodeled`, which gives {name}`Output.unmodeled`;
* a query that succeeds gives {name}`Output.ofResults` of its possible results;
* a write with {lit}`RETURNING` that succeeds gives its rows in normal form, because SQLite
  promises no order for them;
* every other statement that succeeds gives {name}`Output.done` of its number of changes, 0
  when it has none;
* a statement for which the model gives no output gives {name}`Output.unmodeled`. -/
def Output.ofStep (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (before : SqlState)
    (transition : SqlTransition) : Output :=
  match haltError transition with
  | some .unmodeled => .unmodeled unmodeledHere
  | some failure@(.prepare _) | some failure@.transactionAlreadyActive | some failure@.noActiveTransaction
  | some failure@.constraintViolation | some failure@.constraintFail | some failure@.constraintRollback
  | some failure@.integerOverflow | some failure@.datatypeMismatch | some failure@.functionError
  | some failure@.nullColumnDefault | some failure@.nonConstantColumnDefault | some failure@.checkColumnDefault =>
    .error failure.primaryCode
  | none => match statement with
    | .query .. => match possibleOutput clock parameters statement before transition with
      | some results => .ofResults results
      | none => .unmodeled "the model gives no result for this query"
    | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .begin | .commit
    | .rollback | .insert .. | .upsert .. | .update .. | .delete .. | .prepareError _ | .setting .. =>
      match statementOutput clock parameters statement before transition with
      | some output =>
        if statement.returnsRows then .rows (Resolved.normalForm output.rows) else .done (output.changes.getD 0)
      | none => .unmodeled "the model gives no output for this statement"

end Belay.Sqlite.Model
