import Belay.Sqlite.Model.FailingConstraints

set_option doc.verso true

/-! The theorems of {name}`Belay.Sqlite.Model.failingConstraints`: for a write that can fire no
trigger and checks no foreign key, it names at least one constraint exactly when the statement
fails with a constraint error. -/

namespace Belay.Sqlite.Model

/-- For every clock value, counters, list of values, statement, database, error and database
{lit}`reached`, if

* the statement can fire no trigger and checks no foreign key
  ({name}`Resolved.Statement.writeRules` is none),
* {name}`runStatement` with the values fails with the error and {lit}`reached`, and
* the error is a constraint error ({name}`ExecutionError.isConstraint`),

then the candidates of {name}`failingConstraints` with the values are not empty. The formula is weaker than the
intent of the module: it does not say that the constraint that SQLite names is among the
candidates. The tests against the native {lit}`sqlite3` shell check that. Proof sketch: for INSERT, the
checked rows fail ({name}`LiteralData.insertFailure_isSome`); for an INSERT with clauses or
algorithms, the last row fails in {name}`LiteralData.upsertRow`
({name}`LiteralData.upsertSteps_error`, {name}`LiteralData.upsertRowFailure_isSome`); for
UPDATE, the table after it fails ({name}`Catalog.updateReport_ne_nil`); CREATE INDEX names its
index; every other statement fails with no constraint error. -/
theorem failingConstraints_ne_nil {clock : Int} {counters : Counters} {parameters : List Value} {statement : Resolved.Statement}
    {database : Database}
    {reason : ExecutionError} {reached : Database} (plain : statement.writeRules = none)
    (failed : (runStatement clock counters parameters statement database).effect = .error (reason, reached))
    (constraint : reason.isConstraint = true) :
    (failingConstraints clock counters parameters statement database).candidates ≠ [] := by
  unfold failingConstraints
  rw [failed]
  simp only [constraint, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  cases statement with
  | insert target rows returning subqueries rules =>
    cases plain
    simp only [runStatement] at failed ⊢
    cases found : database.table target with
    | none => simp [found] at failed; cases failed.1; simp [ExecutionError.isConstraint] at constraint
    | some table =>
      simp only [found, StatementRun.withKeys, Option.map_none, insertOutcome] at failed ⊢
      apply candidates_getD_ne_nil
      apply LiteralData.insertFailure_isSome
      unfold LiteralData.checkedPrefix
      split at failed
      · rename_i index aliasAt
        simp only [aliasAt]
        split at failed
        · injection failed with failed; injection failed with failed; subst failed
          simp [ExecutionError.isConstraint] at constraint
        · simp_all
      · rename_i noAlias
        simp only [noAlias]
        simp only [checkedWrite] at failed
        split at failed
        · simp at failed
        · simp_all
  | upsert target rows clauses returning algorithm subqueries rules =>
    cases plain
    simp only [runStatement] at failed ⊢
    cases found : database.table target with
    | none => simp [found] at failed; cases failed.1; simp [ExecutionError.isConstraint] at constraint
    | some table =>
      simp only [found, StatementRun.withKeys, Option.map_none] at failed ⊢
      split at failed
      · simp at failed
      · rename_i _ _ _ summary
        injection failed with failed; injection failed with failed; subst failed
        obtain ⟨step, last, stepError⟩ := LiteralData.upsertSteps_error summary
        simp only [last]
        apply candidates_getD_ne_nil
        exact LiteralData.upsertRowFailure_isSome stepError
          (by intro mismatch; subst mismatch; simp [ExecutionError.isConstraint] at constraint)
  | update target assignments filter returning subqueries rules =>
    cases plain
    simp only [runStatement] at failed ⊢
    cases found : database.table target with
    | none => simp [found] at failed; cases failed.1; simp [ExecutionError.isConstraint] at constraint
    | some table =>
      simp only [found, StatementRun.withKeys, Option.map_none] at failed ⊢
      split at failed
      · injection failed with failed; injection failed with failed; subst failed
        simp [ExecutionError.isConstraint] at constraint
      · simp only [checkedWrite] at failed
        split at failed
        · simp at failed
        · exact Catalog.updateReport_ne_nil (by assumption)
  | createIndex _ name index => simp
  | delete | drop | createTable | createTrigger | addColumn | begin | commit | rollback | prepareError | query
  | setting =>
    all_goals first
      | (cases plain; done)
      | (try simp only [Resolved.Statement.writeRules] at plain
         try subst plain
         simp only [runStatement, step, StatementRun.withKeys, queryEffect] at failed
         repeat' split at failed
         all_goals (try injection failed with failed; try injection failed with failed; try subst failed)
         all_goals simp_all [ExecutionError.isConstraint])

/-- For every clock value, counters, list of values, statement and database such that the statement can
fire no trigger and checks no foreign key ({name}`Resolved.Statement.writeRules` is none): the
candidates of {name}`failingConstraints` with the values are empty exactly when every error with
which {name}`runStatement` with the values fails is not a constraint error ({name}`ExecutionError.isConstraint`). So the model names at
least one constraint exactly when the statement fails with a constraint error. The formula is
weaker than the intent: it does not say that SQLite's constraint is among the candidates, which
only the tests against the native {lit}`sqlite3` shell check. A statement that
does not fail satisfies the right side. Proof sketch: from left to right by
{name}`failingConstraints_ne_nil`; from right to left, {name}`failingConstraints` gives no
candidate for a statement that does not fail with a constraint error. -/
theorem failingConstraints_eq_nil_iff {clock : Int} {counters : Counters} {parameters : List Value} {statement : Resolved.Statement}
    {database : Database}
    (plain : statement.writeRules = none) :
    (failingConstraints clock counters parameters statement database).candidates = [] ↔
      ∀ reason reached, (runStatement clock counters parameters statement database).effect = .error (reason, reached) →
        reason.isConstraint = false := by
  constructor
  · intro empty reason reached failed
    cases constraint : reason.isConstraint with
    | false => rfl
    | true => exact absurd empty (failingConstraints_ne_nil plain failed constraint)
  · intro noConstraint
    unfold failingConstraints
    cases effect : (runStatement clock counters parameters statement database).effect with
    | ok _ => rfl
    | error pair =>
      obtain ⟨reason, reached⟩ := pair
      simp [noConstraint reason reached effect]

end Belay.Sqlite.Model
