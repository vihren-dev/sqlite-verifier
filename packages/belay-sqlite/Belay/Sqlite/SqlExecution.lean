import Belay.Sqlite.Execution
import Belay.Sqlite.RowDelete
import Belay.Sqlite.UpsertRun

set_option doc.verso true

/-! Script-directed SQL execution of resolved statements. BEGIN records the
committed snapshot; an explicit COMMIT/ROLLBACK, or an INSERT that fails with the
ROLLBACK algorithm, changes transaction state. Other statement errors stop execution
without inferring connection closure, framework cleanup, or transaction rollback. -/
namespace Belay.Sqlite

/-- The current connection view and optional transaction snapshot. Supply a
database and omit the snapshot for an idle connection. -/
structure SqlState where
  /-- Current connection-visible storage. -/
  database : Database
  /-- Pre-BEGIN committed storage; omit it outside a transaction. -/
  snapshot : Option Database := none

/-- Attach an open transaction to a terminal result. A success becomes pending
without an error; a failure becomes pending with its position/error. An existing
pending result is retained. With no snapshot, return the supplied outcome. -/
def SqlState.finish (state : SqlState) (outcome : Outcome) : Outcome :=
  match state.snapshot, outcome with
  | none, _ => outcome
  | some original, .success result => .pending original result none
  | some original, .failure index reason result => .pending original result (some (index, reason))
  | _, .pending .. => outcome

/-- The outcome of a statement that fails: a ROLLBACK failure in an open transaction
rolls it back, so it is the failure over the snapshot outside a transaction; every other
failure, and a ROLLBACK failure without a transaction, is {name}`SqlState.finish` of the
failure. -/
def SqlState.failed (state : SqlState) (position : Nat) (reason : ExecutionError) (database : Database) : Outcome :=
  if reason = .constraintRollback then match state.snapshot with
    | some original => .failure position reason original
    | none => state.finish (.failure position reason database)
  else state.finish (.failure position reason database)

/-- One SQL transition either continues with a connection state or halts with an
{name}`Outcome`. Evaluate a supplied statement to obtain a transition. -/
inductive SqlTransition where
  /-- Continue with this updated connection state. -/
  | next (state : SqlState)
  /-- Stop with this error or terminal result. -/
  | halt (outcome : Outcome)

/-- Store a write's result when it satisfies the constraints of the given keys and its
rowids are distinct ({name}`LiteralData.rowidsDistinct`), or fail at the position with
{lean}`ExecutionError.constraintViolation` and the input database. -/
def checkedWrite (database : Database) (at_ : Nat) (keys : List (List Nat)) (result : Table)
    (position : Nat) : Outcome :=
  if LiteralData.constraints keys result && LiteralData.rowidsDistinct result then
    .success (database.set at_ result)
  else .failure position .constraintViolation database

/-- The outcome of INSERT: SQLite inserts the rows in order, and refuses a rowid alias
that is not an integer before the constraints of its row
({name}`LiteralData.aliasMismatch`), so the first such row is
{lean}`ExecutionError.datatypeMismatch` unless the rows before it already fail; with no
such row, {name}`checkedWrite` of all rows. A failure keeps the input database. -/
def insertOutcome (database : Database) (at_ : Nat) (keys : List (List Nat)) (table : Table)
    (rows : List (List Value)) (position : Nat) : Outcome :=
  match rows.findIdx? (LiteralData.aliasMismatch table.shape) with
  | some index =>
    let before := LiteralData.inserted table (rows.take index)
    if LiteralData.constraints keys before && LiteralData.rowidsDistinct before then
      .failure position .datatypeMismatch database
    else .failure position .constraintViolation database
  | none => checkedWrite database at_ keys (LiteralData.inserted table rows) position

/-- Apply INSERT/UPDATE with ABORT constraints over the statement's keys, INSERT with
{lit}`ON CONFLICT` clauses row by row ({name}`LiteralData.upsertRun`), and DELETE,
which removes rows and cannot fail a constraint. A position without a table fails as
{lean}`ExecutionError.unmodeled`; a failed constraint retains the input database.
Other statements use {name}`step`. This
computation does not establish the separate stored-value support obligation. -/
def literalStep (statement : Resolved.Statement) (database : Database) (position : Nat) : Outcome :=
  match statement with
  | .insert at_ rows keys _ => match database at_ with
    | none => .failure position .unmodeled database
    | some table => insertOutcome database at_ keys table rows position
  | .upsert at_ rows clauses keys _ policy => match database at_ with
    | none => .failure position .unmodeled database
    | some table => match LiteralData.upsertRun keys policy clauses table rows with
      | .ok (result, _) => .success (database.set at_ result)
      | .error (reason, reached, _) => .failure position reason (LiteralData.failedDatabase database at_ reason reached)
  | .update at_ assignments filter keys _ => match database at_ with
    | none => .failure position .unmodeled database
    | some table =>
      if LiteralData.updateMismatch table assignments filter then .failure position .datatypeMismatch database
      else checkedWrite database at_ keys (LiteralData.updated table assignments filter) position
  | .delete at_ filter _ => match database at_ with
    | none => .failure position .unmodeled database
    | some table => .success (database.set at_ (LiteralData.deleted table filter))
  | .createTable .. | .createIndex .. | .addColumn .. | .begin | .commit | .rollback | .prepareError _ | .query _ =>
    step statement database position

/-- Check that the model describes the statement against the current table.
INSERT/UPDATE must pass the data domain of the table; a position without a table
passes and fails during execution instead. CREATE TABLE and ADD COLUMN must be
plain, and CREATE INDEX fails: these are model restrictions, because SQLite
accepts such statements. Other statement forms pass. Use it through the
reached-statement script support check. -/
def statementReady (statement : Resolved.Statement) (database : Database) : Bool :=
  match statement with
  | .insert at_ rows keys _ => (database at_).all fun table => LiteralData.insertReady keys table rows
  | .upsert at_ rows clauses keys _ policy => (database at_).all fun table =>
      LiteralData.upsertReady keys policy table clauses rows
  | .update at_ assignments filter keys _ => (database at_).all fun table =>
      LiteralData.updateReady keys table assignments filter
  | .delete .. => true
  | .createTable _ _ table => table.plain
  | .addColumn _ column => column.plain
  | .createIndex .. => false
  | .begin | .commit | .rollback | .prepareError _ | .query _ => true

/-- Evaluate one statement at its supplied zero-based position. BEGIN records a
snapshot; COMMIT clears it; ROLLBACK restores it. Repeated BEGIN or transaction
closure without a snapshot halts with an error. Other statements use
{name}`literalStep`; an error retains any open transaction, except a ROLLBACK failure,
which rolls it back ({name}`SqlState.failed`). -/
def advance (position : Nat) (statement : Resolved.Statement) (state : SqlState) : SqlTransition :=
  match statement with
  | .begin => match state.snapshot with
    | some _ => .halt (state.finish (.failure position .transactionAlreadyActive state.database))
    | none => .next { state with snapshot := some state.database }
  | .commit => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some _ => .next { state with snapshot := none }
  | .rollback => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some original => .next { database := original }
  | .createTable .. | .createIndex .. | .addColumn .. | .insert .. | .upsert .. | .update .. | .delete ..
  | .prepareError _ | .query _ =>
    match literalStep statement state.database position with
    | .success database => .next { state with database := database }
    | .failure failed reason database => .halt (state.failed failed reason database)
    | .pending persisted visible error => .halt (state.finish (.pending persisted visible error))

/-- Execute the script from a supplied position and connection state. A halt stops
the script; a continuing transition advances the position. EOF finishes the
current state and preserves an open transaction. The idle wrapper starts at position zero. -/
def runSqlFrom (position : Nat) (script : List Resolved.Statement) (state : SqlState) : Outcome :=
  match script with
  | [] => state.finish (.success state.database)
  | statement :: rest => match advance position statement state with
    | .halt outcome => outcome
    | .next next => runSqlFrom (position + 1) rest next

/-- Execute a resolved script from position zero outside a transaction. Use
{name}`runSqlFrom` for an explicit position/state. A file is not implicitly atomic;
transaction control must be supplied in its statements. -/
def runSql (script : List Resolved.Statement) (database : Database) : Outcome :=
  runSqlFrom 0 script { database := database }

/-- Check {name}`statementReady` at every reached statement and follow the actual
transition. After a halt, unreachable statements impose no obligation. An empty
script passes. -/
def supportedSqlFrom (position : Nat) (script : List Resolved.Statement) (state : SqlState) : Bool :=
  match script with
  | [] => true
  | statement :: rest => statementReady statement state.database &&
    match advance position statement state with
    | .halt _ => true
    | .next next => supportedSqlFrom (position + 1) rest next

/-- For the supplied script and database, the reached-statement data check returns
true. This does not assert native refinement or successful execution. A
verification target proves this obligation for every admitted database; it is not
an extra unproved premise. -/
def SupportedSql (script : List Resolved.Statement) (database : Database) : Prop :=
  supportedSqlFrom 0 script { database := database } = true

/-- Relate each profile, script and starting database to its computed
{name}`runSql` outcome. Every profile currently has this same deterministic
semantics; the profile remains bound into verification inputs. -/
inductive ProfileExecutes : Profile → List Resolved.Statement → Database → Outcome → Prop where
  /-- The computed SQL result is related for every profile, script and database. -/
  | evaluated : ProfileExecutes profile script database (runSql script database)

/-- For every profile, script and starting database, there exists a related
outcome. The computed result supplies the witness, including empty scripts,
errors and pending transactions; outcome coverage is never vacuous. -/
theorem ProfileExecutes.total (profile : Profile) (script : List Resolved.Statement)
    (database : Database) : ∃ outcome, ProfileExecutes profile script database outcome :=
  ⟨_, .evaluated⟩

/-- For every related execution, its outcome equals the computed {name}`runSql`
result for the same script and starting database. The proof inspects the relation
constructor; there are no additional hypotheses. -/
theorem ProfileExecutes.result (execution : ProfileExecutes profile script database outcome) :
    runSql script database = outcome := by cases execution; rfl

end Belay.Sqlite
