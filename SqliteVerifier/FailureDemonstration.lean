import SqliteVerifier.Demonstration

set_option doc.verso true

/-! An explicit failure contract protects the committed prefix's actual storage.
This separate engineering policy permits exactly the expected third-statement error. -/

open Belay.Sqlite

namespace SqliteVerifier.Demonstration

/-- Recreating the audit table fails after both earlier statements have committed. -/
def failureScript : List Statement :=
  script ++ [.createTable "audit" [message], .createTable "unreached" [message]]

/-- Failure applicability is an approved property, not an execution assumption. -/
def failureRequirements : LogicalContract LogicalRows :=
  { requirements with applicability := fun _ outcome =>
      match outcome with
      | .failure 2 (.tableExists "audit") _ => True
      | _ => False }

/-- Read the resulting committed prefix with the same actual invoice projection. -/
def prefixRepresentation : FailureRepresentation LogicalRows where
  schema := fun _ _ => nextSchema
  interpretation := fun _ _ => next

/-- The complete {name}`VerificationConditions` for {name}`failureScript` hold
for every admitted starting database. The first two statements succeed; position
two fails with table-exists and preserves the invoice projection. The proof uses
the successful prefix certificate and the guarded schema-prefix composition law. -/
theorem failureMigrationCorrect :
    VerificationConditions startSchema nextSchema failureScript (fun _ => True)
      failureRequirements current next prefixRepresentation := by
  apply VerificationConditions.of_runSql (contract := failureRequirements)
    migrationCorrect.nonempty migrationCorrect.beforeSound
    migrationCorrect.afterSound
  · intro _ _
    exact migrationCorrect.afterSound
  · exact migrationCorrect.starting
  · intro database _
    exact ⟨by decide +kernel, supportedSqlFrom_schemaOnly (by simp [SchemaOnly, failureScript, script])⟩
  · intro database admitted
    obtain ⟨logical, read, _⟩ :=
      (migrationCorrect.beforeSound database (migrationCorrect.starting database admitted)).2
    have obligations := migrationCorrect.outcomes database admitted _ .evaluated
    simp only [runSql] at obligations
    cases executed : runSqlFrom 0 script { database := database } with
    | failure position reason result =>
      have impossible := obligations.1
      simp [executed, requirements, requiresSuccess] at impossible
    | success result =>
      have preserved := obligations.2
      rw [executed] at preserved
      have conforming := (migrationCorrect.afterSound result (preserved logical read).1).1
      obtain ⟨audit, present, _, _⟩ := conforming.table (name := "audit") (by rfl)
      have auditName : supportedTableName "audit" = true := by decide +kernel
      have auditColumns : supportedColumns [message] = true := by decide +kernel
      have messagePlain : message.plain = true := by decide +kernel
      have failed : runSql failureScript database = .failure 2 (.tableExists "audit") result := by
        simp only [runSql, failureScript]
        rw [runSqlFrom_schemaOnly_append (initial := script) (by simp [SchemaOnly, script]), executed]
        simp [runSqlFrom, advance, literalStep, SqlState.finish, script, step, auditName, auditColumns, messagePlain, present]
      rw [failed]
      refine ⟨trivial, ?_⟩
      intro original observed
      obtain ⟨invariant, _, target, targetRead, unchanged⟩ := preserved original observed
      exact ⟨invariant, target, targetRead, unchanged⟩
    | pending persisted visible error =>
      have impossible := obligations.1
      simp [executed, requirements, requiresSuccess] at impossible

#print axioms failureMigrationCorrect

end SqliteVerifier.Demonstration
