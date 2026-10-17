import SqliteVerifier.Demonstration

set_option doc.verso true

/-! An explicit failure contract protects the committed prefix's actual storage.
This separate engineering policy permits exactly the expected third-statement
error. The resolved script is the one for the migration
{lit}`ALTER TABLE invoices ADD COLUMN note TEXT; CREATE TABLE audit (message TEXT);
CREATE TABLE audit (message TEXT); CREATE TABLE unreached (message TEXT);`: the
second CREATE of {lit}`audit` is SQLite's prepare error. -/

open Belay.Sqlite

namespace SqliteVerifier.Demonstration

/-- Recreating the audit table fails after both earlier statements have committed. -/
def failureScript : List Resolved.Statement :=
  script ++ [.prepareError (.tableExists "audit"), .createTable 2 "unreached" { columns := [message] }]

/-- The catalog after every statement of {name}`failureScript` succeeds. Resolution
continues after a prepare error as if that statement had no effect, so it contains
the unreached table; execution stops before it. -/
def failureNextCatalog : Catalog := nextCatalog ++ [{ name := "unreached", entry := .table { columns := [message] } }]

/-- The invoice projection under {name}`failureNextCatalog`, the target's resulting
catalog. Success never happens, so only its soundness matters. -/
def failureNext (profile : Profile) : Interpretation LogicalRows :=
  projectedInterpretation profile failureNextCatalog "invoices" ["amount"]

/-- Failure applicability is an approved property, not an execution assumption. -/
def failureRequirements : LogicalContract LogicalRows :=
  { requirements with applicability := fun _ outcome =>
      match outcome with
      | .failure 2 (.prepare (.tableExists "audit")) _ => True
      | _ => False }

/-- Read the resulting committed prefix, whose catalog is {name}`nextCatalog`, with the
same actual invoice projection. -/
def prefixRepresentation (profile : Profile) : FailureRepresentation LogicalRows where
  catalog := fun _ _ => nextCatalog
  interpretation := fun _ _ => next profile

/-- The complete {name}`VerificationConditions` for {name}`failureScript` hold for
every admitted starting database and every profile that allows two columns. The
target's resulting catalog is {name}`failureNextCatalog`. The first two statements
succeed; position two fails with SQLite's table-exists
prepare error and preserves the invoice projection. The proof uses the successful
prefix certificate and the guarded schema-prefix composition law. -/
theorem failureMigrationCorrect (profile : Profile) (columns : 2 ≤ profile.limits.columns) :
    VerificationConditions startCatalog failureNextCatalog failureScript (fun _ => True)
      failureRequirements (current profile) (failureNext profile) (prefixRepresentation profile) profile := by
  have checked := migrationCorrect profile columns
  apply VerificationConditions.of_runSql (contract := failureRequirements)
    checked.nonempty checked.beforeSound
    (projectedInterpretation_sound failureRequirements profile failureNextCatalog "invoices" ["amount"]
      (by intros; trivial))
  · intro _ _
    exact checked.afterSound
  · exact checked.starting
  · intro database _
    exact supportedSqlFrom_noWrites (by simp [NoWrites, failureScript, script])
      (by simp [ModeledDefinitions, failureScript, script, CatalogTable.plain, CatalogColumn.plain, readDefaultValue, Except.toOption, note, message])
  · intro database admitted
    obtain ⟨logical, read, _⟩ := (checked.beforeSound database (checked.starting database admitted)).2
    have obligations := checked.outcomes database admitted _ .evaluated
    simp only [runSql] at obligations
    cases executed : runSqlFrom 0 script { database := database } with
    | failure position reason result =>
      have impossible := obligations.1
      simp [executed, requirements, requiresSuccess] at impossible
    | success result =>
      have preserved := obligations.2
      rw [executed] at preserved
      have failed : runSql failureScript database = .failure 2 (.prepare (.tableExists "audit")) result := by
        simp only [runSql, failureScript]
        rw [runSqlFrom_schemaOnly_append (initial := script) (by simp [SchemaOnly, script]), executed]
        simp [runSqlFrom, advance, literalStep, SqlState.finish, script, step]
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
