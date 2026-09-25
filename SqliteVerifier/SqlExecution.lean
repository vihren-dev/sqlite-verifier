import SqliteVerifier.Execution
import SqliteVerifier.LiteralData

/-! Script-directed SQL execution. BEGIN records the committed snapshot; only an
explicit COMMIT/ROLLBACK changes transaction state. Statement errors stop execution
without inferring connection closure, framework cleanup, or transaction rollback. -/
namespace SqliteVerifier

/-- Profiles select fixed SQLite engine settings, never application behavior. -/
inductive ExecutionProfile where
  | sqlite351 | sqlite346
  deriving Repr, DecidableEq

/-- The current connection view and optional pre-BEGIN committed storage. -/
structure SqlState where
  database : Database
  snapshot : Option Database := none

/-- A terminal outcome retains open-transaction visibility and persisted storage. -/
def SqlState.finish (state : SqlState) (outcome : Outcome) : Outcome :=
  match state.snapshot, outcome with
  | none, _ => outcome
  | some original, .success result => .pending original result none
  | some original, .failure index reason result => .pending original result (some (index, reason))
  | _, .pending .. => outcome

/-- Internal statement transitions either continue or stop with the actual outcome. -/
inductive SqlTransition where
  | next (state : SqlState)
  | halt (outcome : Outcome)

/-- Literal writes apply ordinary ABORT constraints atomically at statement scope. -/
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

/-- No execution case silently authorizes unsupported affinities or stored key types. -/
def statementReady (statement : Statement) (database : Database) : Bool :=
  match statement with
  | .insert name columns values => (database name).all (fun table =>
      LiteralData.insertReady table columns values)
  | .update name column value key equals => (database name).all (fun table =>
      LiteralData.updateReady table column value key equals)
  | _ => true

/-- SQL transaction control is ordinary supplied syntax, independent of the profile. -/
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

/-- Execution covers every statement position, including a still-open transaction at EOF. -/
def runSqlFrom (position : Nat) (script : List Statement) (state : SqlState) : Outcome :=
  match script with
  | [] => state.finish (.success state.database)
  | statement :: rest => match advance position statement state with
    | .halt outcome => outcome
    | .next next => runSqlFrom (position + 1) rest next

/-- The public SQL file starts outside a transaction; the file is not implicitly atomic. -/
def runSql (script : List Statement) (database : Database) : Outcome :=
  runSqlFrom 0 script { database := database }

/-- All reached statements must lie inside the modeled data/coercion domain. -/
def supportedSqlFrom (position : Nat) (script : List Statement) (state : SqlState) : Bool :=
  match script with
  | [] => true
  | statement :: rest => statementReady statement state.database &&
    match advance position statement state with
    | .halt _ => true
    | .next next => supportedSqlFrom (position + 1) rest next

/-- CREATE cannot ignore an existing global index-name namespace. This conservative
domain permits CREATE only when the starting schema has no explicit indexes. -/
def schemaAllows (schema : Schema) (script : List Statement) : Bool :=
  !(script.any fun statement => match statement with | .createTable .. => true | _ => false) ||
    schema.all (fun table => table.properties.indexes.isEmpty)

/-- This checked domain obligation cannot be supplied as an unproved extra premise. -/
def SupportedSql (schema : Schema) (script : List Statement) (database : Database) : Prop :=
  schemaAllows schema script = true ∧
    supportedSqlFrom 0 script { database := database } = true

/-- Both pinned engines share precisely this admitted SQL subset; each remains input-bound. -/
inductive ProfileExecutes : ExecutionProfile → List Statement → Database → Outcome → Prop where
  | evaluated : ProfileExecutes profile script database (runSql script database)

/-- Totality rules out vacuous outcome coverage from missing execution constructors. -/
theorem ProfileExecutes.total (profile : ExecutionProfile) (script : List Statement)
    (database : Database) : ∃ outcome, ProfileExecutes profile script database outcome :=
  ⟨_, .evaluated⟩

/-- The relation has exactly the executable semantics, not an unrelated proof oracle. -/
theorem ProfileExecutes.result (execution : ProfileExecutes profile script database outcome) :
    runSql script database = outcome := by cases execution; rfl

end SqliteVerifier
