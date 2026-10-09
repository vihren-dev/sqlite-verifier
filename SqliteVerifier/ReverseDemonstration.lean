import SqliteVerifier.Demonstration

set_option doc.verso true

/-! An independently checked migration reuses the exact same logical contract
and initial interpretation; the proof accounts for its changed statement order. -/

open Belay.Sqlite

namespace SqliteVerifier.Demonstration

/-- Create the independent audit table before extending existing invoices. -/
def reverseScript : List Statement :=
  [.createTable "audit" [message], .addColumn "invoices" note]

/-- For every database admitted by {name}`startSchema` and the true condition,
{name}`reverseScript` and {name}`script` have equal computed SQL outcomes.
There is no claim for unadmitted databases. The proof computes both successful
orders and commutes the updates to their distinct table names. -/
theorem reverse_runs (database : Database) (admitted : Admitted startSchema (fun _ => True) database) :
    runSql reverseScript database = runSql script database := by
  obtain ⟨table, present, columns, _⟩ := admitted.1.table (name := "invoices") (by rfl)
  have absent : database "audit" = none := by
    have shape := (admitted.1.2 "audit").1
    simpa [Schema.lookup, startSchema] using shape
  have invoiceName : supportedTableName "invoices" = true := by decide +kernel
  have noteSupported : supportedColumn note = true := by decide +kernel
  have notePlain : note.plain = true := by decide +kernel
  have auditSupported : (supportedTableName "audit" && supportedColumns [message] && [message].all Column.plain) = true := by decide +kernel
  have noDuplicate : table.columns.any (fun old => old.name == note.name) = false := by
    rw [columns]; decide +kernel
  have belowLimit : table.columns.length < maximumColumns := by rw [columns]; decide
  simp only [runSql, runSqlFrom, advance, literalStep, SqlState.finish, reverseScript, script, step]
  simp only [invoiceName, noteSupported, auditSupported, notePlain, Bool.true_and, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, absent, present, noDuplicate, Nat.not_le.mpr belowLimit]
  have readInvoice : (database.set "audit" { columns := [message], rows := [] }) "invoices" = some table := by
    simp [Database.set, present]
  have readAudit : (database.set "invoices" (table.appendColumns [note])) "audit" = none := by
    simp [Database.set, absent]
  simp only [readInvoice, readAudit, noDuplicate, Nat.not_le.mpr belowLimit,
    Bool.false_eq_true, ↓reduceIte]
  congr 1
  exact database.set_comm "audit" "invoices" { columns := [message], rows := [] } (table.appendColumns [note]) (by decide)

/-- The complete {name}`VerificationConditions` hold for {name}`reverseScript`
with the same approved schemas, contract and interpretations. The proof reuses
{name}`migrationCorrect` through {name}`reverse_runs` and separately proves
the reordered script supported for every admitted starting database. -/
theorem reverseMigrationCorrect :
    VerificationConditions startSchema nextSchema reverseScript (fun _ => True)
      requirements current next unreachableFailures :=
  migrationCorrect.congr_runSql
    (fun _ _ => ⟨by decide +kernel, supportedSqlFrom_schemaOnly (by simp [SchemaOnly, reverseScript])⟩)
    reverse_runs

#print axioms reverseMigrationCorrect

end SqliteVerifier.Demonstration
