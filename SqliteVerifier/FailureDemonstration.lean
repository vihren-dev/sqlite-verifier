import SqliteVerifier.Demonstration

/-! An explicit failure contract protects the committed prefix's actual storage.
This separate engineering policy permits exactly the expected third-statement error. -/

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

/-- A modeled error is safe under this separate explicit policy for all old data. -/
theorem failureMigrationCorrect :
    VerificationConditions startSchema nextSchema failureScript (fun _ => True)
      failureRequirements current next prefixRepresentation := by
  apply VerificationConditions.of_run (contract := failureRequirements)
    (by decide +kernel) (by decide +kernel)
    migrationCorrect.nonempty migrationCorrect.beforeSound
    migrationCorrect.afterSound
  · intro _ _
    exact migrationCorrect.afterSound
  · exact migrationCorrect.starting
  · intro database admitted
    obtain ⟨logical, read, _⟩ :=
      (migrationCorrect.beforeSound database (migrationCorrect.starting database admitted)).2
    have obligations := migrationCorrect.outcomes database admitted _
      (.extensions (by decide +kernel) (runFrom_executes script database 0))
    cases executed : runFrom 0 script database with
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
      have failed : run failureScript database = .failure 2 (.tableExists "audit") result := by
        simp only [run, failureScript, runFrom_append, executed]
        simp [runFrom, script, step, auditName, auditColumns, messagePlain, present]
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
