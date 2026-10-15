import SqliteVerifier.Demonstration

set_option doc.verso true

/-! An independently checked migration reuses the exact same logical contract
and initial interpretation; the proof accounts for its changed statement order.
The resolved script is the one for
{lit}`CREATE TABLE audit(message TEXT); ALTER TABLE invoices ADD COLUMN note TEXT;`. -/

open Belay.Sqlite

namespace SqliteVerifier.Demonstration

/-- Create the independent audit table before extending existing invoices. -/
def reverseScript : List Resolved.Statement :=
  [.createTable 1 "audit" { columns := [message] }, .addColumn 0 note]

/-- For every profile and every database admitted by {name}`startCatalog` and the
true condition, {name}`reverseScript` and {name}`script` have equal computed SQL
outcomes. There is no claim for unadmitted databases. The proof computes both
successful orders and commutes the updates to their distinct positions. -/
theorem reverse_runs (database : Database) (admitted : Admitted profile startCatalog (fun _ => True) database) :
    runSql reverseScript database = runSql script database := by
  obtain ⟨table, present, _, _, absent⟩ := admitted_invoices admitted
  have readInvoice : (database.set 1 { shape := { columns := [message] }, rows := [] }) 0 = some table := by
    simp [Database.set, present]
  have readAudit : (database.set 0 (table.appendColumns [(note, .null)])) 1 = none := by
    simp [Database.set, absent]
  simp only [note, message] at readInvoice readAudit
  have reversed : runSql reverseScript database = .success ((database.set 1
      { shape := { columns := [message] }, rows := [] }).set 0 (table.appendColumns [(note, .null)])) := by
    simp [runSql, runSqlFrom, advance, literalStep, SqlState.finish, reverseScript, step, readDefaultValue, Except.toOption, absent, readInvoice,
      note, message]
  have forward : runSql script database = .success ((database.set 0 (table.appendColumns [(note, .null)])).set 1
      { shape := { columns := [message] }, rows := [] }) := by
    simp [runSql, runSqlFrom, advance, literalStep, SqlState.finish, script, step, readDefaultValue, Except.toOption, present, readAudit,
      note, message]
  rw [reversed, forward, database.set_comm 1 0 _ _ (by decide)]

/-- The complete {name}`VerificationConditions` hold for {name}`reverseScript` with
the same approved catalogs, contract and interpretations, under every profile that
allows two columns. The proof reuses {name}`migrationCorrect` through
{name}`reverse_runs` and separately proves the reordered script supported for
every admitted starting database. -/
theorem reverseMigrationCorrect (profile : Profile) (columns : 2 ≤ profile.limits.columns) :
    VerificationConditions startCatalog nextCatalog reverseScript (fun _ => True)
      requirements (current profile) (next profile) unreachableFailures profile :=
  (migrationCorrect profile columns).congr_runSql
    (fun _ _ => supportedSqlFrom_schemaOnly (by simp [SchemaOnly, reverseScript])
      (by simp [ModeledDefinitions, reverseScript, CatalogTable.plain, CatalogColumn.plain, readDefaultValue, Except.toOption, note, message]))
    reverse_runs

#print axioms reverseMigrationCorrect

end SqliteVerifier.Demonstration
