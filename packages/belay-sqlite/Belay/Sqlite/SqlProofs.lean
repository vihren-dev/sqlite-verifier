import Belay.Sqlite.SqlExecution

set_option doc.verso true

/-! Schema-only proof laws for the full SQL executor. Keeping these guarded
conveniences separate leaves the statement and transaction semantics in one module. -/

namespace Belay.Sqlite

/-- For every database, position, reason and result database, the failure of an idle
state is the plain failure. Proof sketch: without a snapshot both branches of the reason
test finish to the failure itself. -/
@[simp] theorem SqlState.failed_idle (current : Database) (position : Nat) (reason : ExecutionError)
    (database : Database) : ({ database := current } : SqlState).failed position reason database =
      .failure position reason database := by
  unfold SqlState.failed SqlState.finish
  split <;> rfl

/-- The error of an outcome: the reason of a failure, the error of a pending result, or
none. -/
def Outcome.error? : Outcome → Option ExecutionError
  | .success _ => none
  | .failure _ reason _ => some reason
  | .pending _ _ error => error.map (·.2)

/-- For every state, position, reason and database, the error of
{name}`SqlState.failed` is the reason. Proof sketch: split on the ROLLBACK test and the
snapshot; each branch is the failure, or the pending result that carries its reason. -/
theorem SqlState.failed_error (state : SqlState) (position : Nat) (reason : ExecutionError) (database : Database) :
    (state.failed position reason database).error? = some reason := by
  unfold SqlState.failed SqlState.finish
  split <;> (try split) <;> (try split) <;> simp_all [Outcome.error?]

/-- For every state, position, reason other than ROLLBACK and database:
{name}`SqlState.failed` has that database as its visible database, and the saved snapshot
when present, or else that database, as its persisted database. Proof sketch: the
ROLLBACK test fails, so the result is {name}`SqlState.finish` of the failure; split on the
snapshot. -/
theorem SqlState.failed_database (state : SqlState) (position : Nat) (reason : ExecutionError) (database : Database)
    (other : reason ≠ .constraintRollback) :
    (state.failed position reason database).database = database ∧
    (state.failed position reason database).persistedDatabase = state.snapshot.getD database := by
  unfold SqlState.failed
  split
  · contradiction
  · cases h : state.snapshot <;> simp [SqlState.finish, h, Outcome.database, Outcome.persistedDatabase]

/-- For every state, position and database: {name}`SqlState.failed` of a ROLLBACK
failure has the saved snapshot when present, or else that database, as its visible and
its persisted database. Proof sketch: the ROLLBACK test holds; split on the snapshot,
which gives the failure over the snapshot or the finished failure. -/
theorem SqlState.failed_rollback (state : SqlState) (position : Nat) (database : Database) :
    (state.failed position .constraintRollback database).database = state.snapshot.getD database ∧
    (state.failed position .constraintRollback database).persistedDatabase = state.snapshot.getD database := by
  unfold SqlState.failed
  split
  · cases h : state.snapshot <;> simp [SqlState.finish, h, Outcome.database, Outcome.persistedDatabase]
  · contradiction

/-- Every statement in the script is CREATE TABLE or ADD COLUMN. This is a syntax
guard, not a validity or success claim. The empty script satisfies it; CREATE
INDEX, transaction control, literal writes and prepare errors do not. Use it for
schema preservation laws. -/
def SchemaOnly (script : List Resolved.Statement) : Prop :=
  ∀ statement ∈ script, match statement with
    | .createTable .. | .addColumn .. => True
    | .createIndex .. => False
    | .begin => False
    | .commit => False
    | .rollback => False
    | .insert .. => False
    | .upsert .. => False
    | .update .. => False
    | .delete .. => False
    | .prepareError _ => False
    | .query _ => False
    | .clocked .. => False

/-- No statement in the script is INSERT (with or without {lit}`ON CONFLICT`, or with
cells that read the clock), UPDATE or DELETE, and no query has a JSON call in its expressions
({name}`Resolved.Query.expressions`, {name}`Resolved.Expr.callsJson`) or a {lit}`json_each`
source. This is a syntax guard, not a success claim; the empty script satisfies it. -/
def NoWrites (script : List Resolved.Statement) : Prop :=
  ∀ statement ∈ script, match statement with
    | .insert .. => False
    | .upsert .. => False
    | .update .. => False
    | .delete .. => False
    | .clocked .. => False
    | .query query => query.expressions.all (!·.callsJson) = true ∧ query.functions = []
    | .createTable .. | .createIndex .. | .addColumn .. | .begin | .commit | .rollback | .prepareError _ => True

/-- Each definition in the script is one that the model describes: each CREATE
TABLE creates a {name}`CatalogTable.plain` table, each ADD COLUMN has a successful
{name}`readDefaultValue` result, and no statement is CREATE INDEX. Other
statements are unrestricted; the empty script satisfies it. -/
def ModeledDefinitions (script : List Resolved.Statement) : Prop :=
  ∀ statement ∈ script, match statement with
    | .createTable _ _ table => table.plain = true
    | .addColumn _ column => (column.clockDefault || (readDefaultValue column).toOption.isSome) = true
    | .createIndex .. => False
    | .insert .. | .upsert .. | .update .. | .delete .. | .clocked .. | .begin | .commit | .rollback | .prepareError _
    | .query _ => True

/-- For every position and connection state, a {name}`NoWrites` script with
{name}`ModeledDefinitions` passes the reached-statement support check, because
only writes and queries have a data check, and a query without a JSON call passes it. The proof inducts over the script and follows
each actual transition. -/
theorem supportedSqlFrom_noWrites (guard : NoWrites script) (modeled : ModeledDefinitions script) :
    supportedSqlFrom position script state = true := by
  induction script generalizing position state with
  | nil => rfl
  | cons statement rest ih =>
    have first := guard statement (by simp)
    have firstModeled := modeled statement (by simp)
    have tail : NoWrites rest := fun item member => guard item (by simp [member])
    have tailModeled : ModeledDefinitions rest := fun item member => modeled item (by simp [member])
    have ready : statementReady statement state.database = true := by
      cases statement with
      | query query =>
        obtain ⟨plain, noFunctions⟩ : (query.expressions.all fun x => !x.callsJson) = true ∧ query.functions = [] :=
          first
        simp [statementReady, queryJsonReady, Resolved.Query.mayFail_of_callsJson query _ plain,
          eachJsonReady_plain query _ noFunctions]
      | createTable | createIndex | addColumn | begin | commit | rollback | insert | upsert | update | delete
      | prepareError | clocked => simp_all [statementReady]
    simp only [supportedSqlFrom, ready, Bool.true_and]
    cases advance position statement state with
    | halt outcome => rfl
    | next next => exact ih tail tailModeled

/-- For every position and connection state, a {name}`SchemaOnly` script with
{name}`ModeledDefinitions` passes the reached-statement support check. It
follows from {name}`supportedSqlFrom_noWrites`, because a schema-only script has
no writes. -/
theorem supportedSqlFrom_schemaOnly (guard : SchemaOnly script) (modeled : ModeledDefinitions script) :
    supportedSqlFrom position script state = true :=
  supportedSqlFrom_noWrites (fun statement member => by
    have first := guard statement member
    cases statement <;> simp_all) modeled

/-- For every position and idle database, a guarded schema statement uses the
primitive transition. The proof splits on the statement and uses the guard to
exclude transaction control and literal-write constructors. -/
theorem advance_schemaOnly
    (guard : SchemaOnly [statement]) :
    advance position statement { database := database } =
      match step statement database position with
      | .success result => .next { database := result }
      | .failure index reason result => .halt (.failure index reason result)
      | .pending persisted visible error => .halt (.pending persisted visible error) := by
  have first := guard statement (by simp)
  cases statement <;> simp_all [advance, literalStep, SqlState.finish]
  all_goals rfl

/-- For every idle starting database and position, appending a suffix to a
{name}`SchemaOnly` prefix resumes at its next position after success and retains
its stopped error otherwise. The prefix cannot open a transaction. This law does
not describe transaction prefixes; their EOF pending state must be resumed with
its committed snapshot. The proof inducts over primitive schema transitions. -/
theorem runSqlFrom_schemaOnly_append (guard : SchemaOnly initial) :
    runSqlFrom position (initial ++ suffix) { database := database } =
      match runSqlFrom position initial { database := database } with
      | .success result => runSqlFrom (position + initial.length) suffix { database := result }
      | .failure index reason result => .failure index reason result
      | .pending persisted visible error => .pending persisted visible error := by
  induction initial generalizing database position with
  | nil => simp [runSqlFrom, SqlState.finish]
  | cons statement rest ih =>
    have first : SchemaOnly [statement] := fun item member => by
      simp only [List.mem_singleton] at member
      subst item
      exact guard statement (by simp)
    have tail : SchemaOnly rest := fun item member => guard item (by simp [member])
    simp only [List.cons_append, runSqlFrom, advance_schemaOnly first]
    cases executed : step statement database position with
    | failure index reason result => rfl
    | pending persisted visible error => rfl
    | success result => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        (ih tail (database := result) (position := position + 1))

/-!
```lean
example : Belay.Sqlite.SchemaOnly [] := by
  intro statement member
  simp at member
example : ¬ Belay.Sqlite.SchemaOnly [Belay.Sqlite.Resolved.Statement.begin] := by
  intro guard
  exact guard .begin (by simp)
```
-/

end Belay.Sqlite
