import Belay.Sqlite.Model.StatementStep
import Belay.Sqlite.Model.SqlCounted

set_option doc.verso true

/-! The steps of script-directed SQL execution of resolved statements. Each statement runs
at the clock value that the state's clock assignment gives for its position;
{lit}`SqlExecution.lean` chooses the assignment. BEGIN records the
committed snapshot; an explicit COMMIT/ROLLBACK, or an INSERT that fails with the
ROLLBACK algorithm, changes transaction state. Other statement errors stop execution
without inferring connection closure, framework cleanup, or transaction rollback. A statement
that continues also gives the counters of the connection their new values (ADR 0024). -/
namespace Belay.Sqlite.Model

/-- One statement at its supplied zero-based position with its effect. BEGIN records a
snapshot; COMMIT clears it; ROLLBACK restores it. Repeated BEGIN or transaction
closure without a snapshot halts with an error. Other statements use
the effect, which {lit}`advance` computes at the clock value of the position
({name}`SqlState.clock`); an error retains any open transaction, except a ROLLBACK failure,
which rolls it back ({name}`SqlState.failed`). -/
def advanceWith (position : Nat) (statement : Resolved.Statement) (state : SqlState) (effect : Effect) :
    SqlTransition :=
  match statement with
  | .begin => match state.snapshot with
    | some _ => .halt (state.finish (.failure position .transactionAlreadyActive state.database))
    | none => .next { state with snapshot := some state.database }
  | .commit => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some _ => .next { state with snapshot := none }
  | .rollback => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some original => .next { state with database := original, snapshot := none }
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .insert .. | .upsert .. | .update ..
  | .delete ..
  | .prepareError _ | .query .. | .setting .. =>
    state.publish position effect

/-- The transition of a statement after its run ({name}`StatementRun`): {name}`advanceWith` of
its effect, with its counts for the counters ({name}`SqlTransition.counted`). -/
def advanceRun (position : Nat) (statement : Resolved.Statement) (state : SqlState) (run : StatementRun) :
    SqlTransition :=
  (advanceWith position statement state run.effect).counted run.counts

/-- Evaluate one statement with the values bound to its parameters at its supplied zero-based
position ({name}`advanceRun` of its run at the clock value of the position,
{name}`runStatement`). -/
def advance (position : Nat) (statement : Resolved.Statement) (parameters : List Value) (state : SqlState) :
    SqlTransition :=
  advanceRun position statement state (SqlState.statementRun state (state.clock position) parameters statement)

/-- For every position, statement, values, state and next state: if {name}`advance` continues
with the next state, then {name}`advanceWith` of the effect ({name}`literalStep`) continues with a
state, and the next state is that state with the counters after the counts of the run. Proof
sketch: {name}`SqlTransition.counted_eq_next`. -/
theorem advance_eq_next {position : Nat} {statement : Resolved.Statement} {parameters : List Value} {state next : SqlState}
    (continued : advance position statement parameters state = .next next) :
    ∃ transitioned, advanceWith position statement state
        ((SqlState.statementRun state (state.clock position) parameters statement).effect) = .next transitioned ∧
      next = { transitioned with
        counters := transitioned.counters.apply (SqlState.statementRun state (state.clock position) parameters statement).counts } :=
  SqlTransition.counted_eq_next.mp continued

/-- For every position, statement, values, state and outcome: if {name}`advance` halts with the
outcome, then {name}`advanceWith` of the effect ({name}`literalStep`) halts with it. Proof sketch:
{name}`SqlTransition.counted_eq_halt`. -/
theorem advance_eq_halt {position : Nat} {statement : Resolved.Statement} {parameters : List Value} {state : SqlState}
    {outcome : Outcome} (halted : advance position statement parameters state = .halt outcome) :
    advanceWith position statement state ((SqlState.statementRun state (state.clock position) parameters statement).effect) =
      .halt outcome :=
  SqlTransition.counted_eq_halt.mp halted

/-- The statements of a script with the values bound to each: statement {lit}`i` (from 0) gets
item {lit}`i` of {lit}`values`, or the empty list when {lit}`values` has no such item. For
example, {lean}`bindValues [1, 2] [[.integer 5]] = [(1, [.integer 5]), (2, [])]`. Use
{lean}`([] : List (List Value))` as {lit}`values` for a script that binds no values. -/
def bindValues {α : Type} : List α → List (List Value) → List (α × List Value)
  | [], _ => []
  | statement :: rest, values => (statement, values.headD []) :: bindValues rest values.tail

/-- For every statement, rest of the script, list of values and rest of the lists,
{name}`bindValues` of the script and the lists is the pair of the first statement and the first
list, followed by {name}`bindValues` of the rest of the script and the rest of the lists. Proof
sketch: the definition. -/
@[simp] theorem bindValues_cons_cons {α : Type} (statement : α) (rest : List α) (values : List Value)
    (later : List (List Value)) :
    bindValues (statement :: rest) (values :: later) = (statement, values) :: bindValues rest later := rfl

/-- For every script and list of lists of values, the statements of {name}`bindValues` are the
script. Proof sketch: induction on the script. -/
@[simp] theorem map_fst_bindValues {α : Type} (script : List α) (values : List (List Value)) :
    (bindValues script values).map (·.1) = script := by
  induction script generalizing values with
  | nil => rfl
  | cons statement rest ih => simp [bindValues, ih]

/-- Execute the script from a supplied position and connection state, each statement with the
values bound to its parameters ({name}`bindValues` binds a list of lists). A halt stops
the script; a continuing transition advances the position. EOF finishes the
current state and preserves an open transaction. The idle wrapper starts at position zero. -/
def runSqlFrom (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Outcome :=
  match script with
  | [] => state.finish (.success state.database)
  | (statement, parameters) :: rest => match advance position statement parameters state with
    | .halt outcome => outcome
    | .next next => runSqlFrom (position + 1) rest next

/-- Execute a resolved script from position zero outside a transaction. Use
{name}`runSqlFrom` for an explicit position/state. A file is not implicitly atomic;
transaction control must be supplied in its statements. -/
def runSql (script : List (Resolved.Statement × List Value)) (database : Database) : Outcome :=
  runSqlFrom 0 script { database := database }

/-- Check {name}`statementReady` at every reached statement and follow the actual
transition, both from one run of the statement ({name}`runStatement`). After a halt,
unreachable statements impose no obligation. An empty script passes. -/
def supportedSqlFrom (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Bool :=
  match script with
  | [] => true
  | (statement, parameters) :: rest =>
    let run := SqlState.statementRun state (state.clock position) parameters statement
    run.ready &&
    match advanceRun position statement state run with
    | .halt _ => true
    | .next next => supportedSqlFrom (position + 1) rest next

end Belay.Sqlite.Model
