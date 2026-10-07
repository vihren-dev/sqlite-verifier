import SqliteVerifier.Execution
import SqliteVerifier.LiteralData

set_option doc.verso true

/-! Script-directed SQL execution. BEGIN records the committed snapshot; only an
explicit COMMIT/ROLLBACK changes transaction state. Statement errors stop execution
without inferring connection closure, framework cleanup, or transaction rollback. -/
namespace SqliteVerifier

/-- Select a pinned engine profile. Use {lean}`ExecutionProfile.sqlite351` for
SQLite 3.51.0. Profiles select engine settings, not framework behavior. -/
inductive ExecutionProfile where
  /-- SQLite 3.51.0 with its pinned settings. -/
  | sqlite351
  /-- SQLite 3.46.0 with its pinned settings. -/
  | sqlite346
  deriving Repr, DecidableEq

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

/-- One SQL transition either continues with a connection state or halts with an
{name}`Outcome`. Evaluate a supplied statement to obtain a transition. -/
inductive SqlTransition where
  /-- Continue with this updated connection state. -/
  | next (state : SqlState)
  /-- Stop with this error or terminal result. -/
  | halt (outcome : Outcome)

/-- Apply literal INSERT/UPDATE and retained ABORT constraints. An absent table
or failed constraint retains the input database. Other statements use {name}`step`.
This computation does not establish the separate stored-value support obligation. -/
def literalStep (statement : Statement) (database : Database) (position : Nat) : Outcome :=
  match statement with
  | .insert name _ _ | .update name _ _ _ _ =>
    match database name with
    | none => .failure position (.missingTable name) database
    | some table =>
      let result := match statement with
        | .insert _ _ values => LiteralData.inserted table values
        | .update _ column value key equals => LiteralData.updated table column value key equals
        | _ => table
      if LiteralData.constraints result then .success (database.set name result)
      else .failure position .constraintViolation database
  | _ => step statement database position

/-- Check INSERT/UPDATE coercion and key support against the current table. An
absent table passes this domain check and fails during execution instead. Other
statement forms pass. Use it through the reached-statement script support check. -/
def statementReady (statement : Statement) (database : Database) : Bool :=
  match statement with
  | .insert name columns values => (database name).all (fun table =>
      LiteralData.insertReady table columns values)
  | .update name column value key equals => (database name).all (fun table =>
      LiteralData.updateReady table column value key equals)
  | _ => true

/-- Evaluate one statement at its supplied zero-based position. BEGIN records a
snapshot; COMMIT clears it; ROLLBACK restores it. Repeated BEGIN or transaction
closure without a snapshot halts with an error. Other statements use
{name}`literalStep`; an error retains any open transaction through
{name}`SqlState.finish`. The profile does not add transaction syntax. -/
def advance (position : Nat) (statement : Statement) (state : SqlState) : SqlTransition :=
  match statement with
  | .beginTransaction => match state.snapshot with
    | some _ => .halt (state.finish (.failure position .transactionAlreadyActive state.database))
    | none => .next { state with snapshot := some state.database }
  | .commit => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some _ => .next { state with snapshot := none }
  | .rollback => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some original => .next { database := original }
  | _ => match literalStep statement state.database position with
    | .success database => .next { state with database := database }
    | outcome => .halt (state.finish outcome)

/-- Execute the script from a supplied position and connection state. A halt stops
the script; a continuing transition advances the position. EOF finishes the
current state and preserves an open transaction. The idle wrapper starts at position zero. -/
def runSqlFrom (position : Nat) (script : List Statement) (state : SqlState) : Outcome :=
  match script with
  | [] => state.finish (.success state.database)
  | statement :: rest => match advance position statement state with
    | .halt outcome => outcome
    | .next next => runSqlFrom (position + 1) rest next

/-- Execute a SQL file from position zero outside a transaction. Use
{name}`runSqlFrom` for an explicit position/state. A file is not implicitly atomic;
transaction control must be supplied in its statements. -/
def runSql (script : List Statement) (database : Database) : Outcome :=
  runSqlFrom 0 script { database := database }

/-- Check {name}`statementReady` at every reached statement and follow the actual
transition. After a halt, unreachable statements impose no obligation. An empty
script passes. Combine this with the schema admission check in verification obligations. -/
def supportedSqlFrom (position : Nat) (script : List Statement) (state : SqlState) : Bool :=
  match script with
  | [] => true
  | statement :: rest => statementReady statement state.database &&
    match advance position statement state with
    | .halt _ => true
    | .next next => supportedSqlFrom (position + 1) rest next

/-- Permit scripts without CREATE, or require every starting table to have no
explicit indexes. This conservative check avoids an unmodeled global index-name
collision during CREATE. An empty schema or a script without CREATE passes. -/
def schemaAllows (schema : Schema) (script : List Statement) : Bool :=
  !(script.any fun statement => match statement with | .createTable .. => true | _ => false) ||
    schema.all (fun table => table.properties.indexes.isEmpty)

/-- For the supplied schema, script and database, require schema admission and
the reached-statement data check to both return true. This does not assert native
refinement or successful execution. A verification target proves this obligation
for every admitted database; it is not an extra unproved premise. -/
def SupportedSql (schema : Schema) (script : List Statement) (database : Database) : Prop :=
  schemaAllows schema script = true ∧
    supportedSqlFrom 0 script { database := database } = true

/-- Relate each pinned profile, script and starting database to its computed
{name}`runSql` outcome. Both profiles currently have this same deterministic
semantics; the profile remains bound into verification inputs. -/
inductive ProfileExecutes : ExecutionProfile → List Statement → Database → Outcome → Prop where
  /-- The computed SQL result is related for every profile, script and database. -/
  | evaluated : ProfileExecutes profile script database (runSql script database)

/-- For every profile, script and starting database, there exists a related
outcome. The computed result supplies the witness, including empty scripts,
errors and pending transactions; outcome coverage is never vacuous. -/
theorem ProfileExecutes.total (profile : ExecutionProfile) (script : List Statement)
    (database : Database) : ∃ outcome, ProfileExecutes profile script database outcome :=
  ⟨_, .evaluated⟩

/-- For every related execution, its outcome equals the computed {name}`runSql`
result for the same script and starting database. The proof inspects the relation
constructor; there are no additional hypotheses. -/
theorem ProfileExecutes.result (execution : ProfileExecutes profile script database outcome) :
    runSql script database = outcome := by cases execution; rfl

end SqliteVerifier
