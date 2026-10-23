import Belay.Sqlite.Model.SqlExecution
import Belay.Sqlite.Model.SqlStateLaws
import Belay.Sqlite.Model.QueryPlainLaws
import Belay.Sqlite.Model.Resolution.StatementCatalog

set_option doc.verso true

/-! Schema-only proof laws for the full SQL executor. Keeping these guarded
conveniences separate leaves the statement and transaction semantics in one module. -/

namespace Belay.Sqlite.Model

/-- Every statement in the script is CREATE TABLE or ADD COLUMN. This is a syntax
guard, not a validity or success claim. The empty script satisfies it; CREATE
INDEX, transaction control, literal writes and prepare errors do not. Use it for
schema preservation laws. -/
def SchemaOnly (script : List Resolved.Statement) : Prop :=
  ∀ statement ∈ script, statement.kind = .definition

/-- No statement in the script is INSERT (with or without {lit}`ON CONFLICT`, or with
cells that read the clock), UPDATE or DELETE, no DROP TABLE deletes rows for foreign keys, and
no query has a fallible call (a JSON call or
a function that can fail) in its expressions ({name}`Resolved.Query.expressions`,
{name}`Resolved.Expr.isFallibleCall` at any depth) or a {lit}`json_each`
source. This is a syntax guard, not a success claim; the empty script satisfies it. Each
statement:
* is not a write ({name}`Resolved.Statement.Kind.write`),
* if it is a DROP, checks no foreign keys, and
* if it is a query, has no subqueries, no {lit}`DISTINCT`, no fallible call, no
  {lit}`json_each` source and no compound terms ({name}`Resolved.Query.compound`). -/
def NoWrites (script : List Resolved.Statement) : Prop :=
  ∀ statement ∈ script, statement.kind ≠ .write ∧
    (∀ positions keys, statement = .drop positions keys → keys = none) ∧
    ∀ query subqueries, statement = .query query subqueries →
    subqueries = [] ∧ query.distinct = none ∧ query.expressions.all (!·.any Resolved.Expr.isFallibleCall) = true ∧
      query.sources.all (!·.source.isEach) = true ∧ query.compound = none

/-- Each definition in the script is one that the model describes: each ADD COLUMN has a time
default ({name}`CatalogColumn.clockDefault`) or a successful {name}`readDefaultValue` result,
and no statement is CREATE INDEX. Every CREATE TABLE and every other statement is
unrestricted; the empty script satisfies it. -/
def ModeledDefinitions (script : List Resolved.Statement) : Prop :=
  ∀ statement ∈ script, match statement with
    | .createTable .. => True
    | .addColumn _ column => (column.clockDefault || (readDefaultValue column).toOption.isSome) = true
    | .createIndex .. => False
    | .createTrigger .. | .drop .. => True
    | .insert .. | .upsert .. | .update .. | .delete .. | .begin | .commit | .rollback | .prepareError _
    | .query .. | .setting .. => True

/-- For every position and connection state, and every script of statements with values whose
statements are {name}`NoWrites` with {name}`ModeledDefinitions`, the script passes the
reached-statement support check, for every list of values of each statement, because
only writes and queries have a data check, and a query without a fallible call passes it. The proof inducts over the script and follows
each actual transition. -/
theorem supportedSqlFrom_noWrites (guard : NoWrites (script.map (·.1)))
    (modeled : ModeledDefinitions (script.map (·.1))) : supportedSqlFrom position script state = true := by
  induction script generalizing position state with
  | nil => rfl
  | cons entry rest ih =>
    obtain ⟨statement, parameters⟩ := entry
    have first := guard statement (by simp)
    have firstModeled := modeled statement (by simp)
    have tail : NoWrites (rest.map (·.1)) := fun item member => guard item (by simp_all)
    have tailModeled : ModeledDefinitions (rest.map (·.1)) := fun item member => modeled item (by simp_all)
    have ready : statementReady (state.clock position) parameters statement state.database = true := by
      cases statement with
      | query query subqueries =>
        obtain ⟨none, single, plain, noEach, single_select⟩ : subqueries = [] ∧ query.distinct = none ∧
            (query.expressions.all fun x => !x.any Resolved.Expr.isFallibleCall) = true ∧
            query.sources.all (!·.source.isEach) = true ∧ query.compound = none := first.2.2 query subqueries rfl
        subst none
        simp only [statementReady, runStatement, Resolved.Query.runOn, Resolved.statementContext_nil,
          Resolved.Query.nestedSubqueries, single_select, Resolved.subqueriesPlain, List.all_nil, Bool.true_and]
        cases found : query.source { Resolved.EvalContext.plain (state.clock position) with parameters }
            state.database with
        | none => rfl
        | some source =>
          have clean := Resolved.source_fault_of_plain _ state.database query.sources _ source noEach rfl found
          cases window : query.bindWindow parameters with
          | none => simp [Resolved.Query.run, single_select, window, clean]
          | some bound =>
            obtain ⟨_, _, shape⟩ := Resolved.Query.bindWindow_some parameters query bound window
            have boundSingle : bound.distinct = none := by rw [shape]; exact single
            have boundPlain : (bound.expressions.all fun x => !x.any Resolved.Expr.isFallibleCall) = true := by
              rw [shape]; exact plain
            by_cases must : bound.mustFail { Resolved.EvalContext.plain (state.clock position) with parameters }
                source.rows = true <;>
              simp [Resolved.Query.run, single_select, window, Resolved.Query.mayFail_of_plain
                  { Resolved.EvalContext.plain (state.clock position) with parameters } (fun _ _ => ⟨rfl, rfl, rfl⟩)
                  bound _ boundPlain, clean, must, Resolved.Query.distinctCertain, boundSingle]
      | drop positions keys =>
        have none := first.2.1 positions keys rfl
        subst none
        simp [statementReady, runStatement, StatementRun.withKeys]
      | createTable | createIndex | createTrigger | addColumn | begin | commit | rollback | insert | upsert | update | delete
      | prepareError | setting => simp_all [statementReady, runStatement]
    have run : (runStatement (state.clock position) parameters statement state.database).ready = true := ready
    simp only [supportedSqlFrom, run, Bool.true_and]
    cases advanceWith position statement state (runStatement (state.clock position) parameters statement state.database).effect with
    | halt outcome => rfl
    | next next => exact ih tail tailModeled

/-- For every position and connection state, and every script of statements with values whose
statements are {name}`SchemaOnly` with {name}`ModeledDefinitions`, the script passes the
reached-statement support check, for every list of values of each statement. It
follows from {name}`supportedSqlFrom_noWrites`, because a schema-only script has
no writes. -/
theorem supportedSqlFrom_schemaOnly (guard : SchemaOnly (script.map (·.1)))
    (modeled : ModeledDefinitions (script.map (·.1))) : supportedSqlFrom position script state = true :=
  supportedSqlFrom_noWrites (fun statement member => by
    have first := guard statement member
    cases statement <;> simp_all) modeled

/-- For every clock value, list of values, statement, database, reason and kept database: if
{name}`step` fails with the reason and the kept database, the kept database is the input database.
Proof sketch: every error branch of {name}`step` keeps its input. -/
theorem step_error_keeps {clock : Int} {parameters : List Value} {statement : Resolved.Statement}
    {database kept : Database} {reason : ExecutionError}
    (failed : step clock parameters statement database = .error (reason, kept)) : kept = database := by
  cases statement <;> simp only [step, queryEffect] at failed
  all_goals (repeat' split at failed)
  all_goals first | (cases failed; rfl) | cases failed

/-- For every position, list of values and idle database, a guarded schema statement with the
values uses the primitive transition at the clock value 0 with the values: success continues with the result, and an error halts with the
error at the position over the input database. The proof splits on the statement, uses
the guard to exclude transaction control and literal-write constructors, and
{name}`step_error_keeps` for the database of an error. -/
theorem advance_schemaOnly
    (guard : SchemaOnly [statement]) :
    advance position statement parameters { database := database } =
      match step 0 parameters statement database with
      | .ok result => .next { database := result }
      | .error (reason, _) => .halt (.failure position reason database) := by
  have first := guard statement (by simp)
  have literal : literalStep 0 parameters statement database = step 0 parameters statement database := by
    cases statement <;> simp_all [literalStep, runStatement]
  have control : statement.isControl = false := by cases statement <;> simp_all [Resolved.Statement.isControl]
  have ordinary : advance position statement parameters { database := database } =
      ({ database := database } : SqlState).publish position (step 0 parameters statement database) := by
    cases statement <;> simp_all [advance, advanceWith, Resolved.Statement.isControl]
  rw [ordinary]
  cases stepped : step 0 parameters statement database with
  | ok result => rfl
  | error failure =>
    obtain ⟨reason, kept⟩ := failure
    have same := step_error_keeps stepped
    subst same
    simp [SqlState.publish]

/-- For every idle starting database and position, appending a suffix to a prefix whose
statements are {name}`SchemaOnly`, each statement of both with any values, resumes at its next position after success and retains
its stopped error otherwise. The prefix cannot open a transaction. This law does
not describe transaction prefixes; their EOF pending state must be resumed with
its committed snapshot. The proof inducts over primitive schema transitions. -/
theorem runSqlFrom_schemaOnly_append (guard : SchemaOnly (initial.map (·.1))) :
    runSqlFrom position (initial ++ suffix) { database := database } =
      match runSqlFrom position initial { database := database } with
      | .success result => runSqlFrom (position + initial.length) suffix { database := result }
      | .failure index reason result => .failure index reason result
      | .pending persisted visible error => .pending persisted visible error := by
  induction initial generalizing database position with
  | nil => simp [runSqlFrom, SqlState.finish]
  | cons entry rest ih =>
    obtain ⟨statement, parameters⟩ := entry
    have first : SchemaOnly [statement] := fun item member => by
      simp only [List.mem_singleton] at member
      subst item
      exact guard statement (by simp)
    have tail : SchemaOnly (rest.map (·.1)) := fun item member => guard item (by simp_all)
    simp only [List.cons_append, runSqlFrom, advance_schemaOnly first]
    cases executed : step 0 parameters statement database with
    | error failure => rfl
    | ok result => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        (ih tail (database := result) (position := position + 1))

/-!
```lean
example : Belay.Sqlite.Model.SchemaOnly [] := by
  intro statement member
  simp at member
example : ¬ Belay.Sqlite.Model.SchemaOnly [Belay.Sqlite.Model.Resolved.Statement.begin] := by
  intro guard
  exact absurd (guard .begin (by simp)) (by decide)
```
-/

end Belay.Sqlite.Model
