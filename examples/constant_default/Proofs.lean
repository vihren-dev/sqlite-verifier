import Generated
import Belay.Sqlite.SchemaExtension

set_option doc.verso true

/-! Prove successful default initialization for every admitted invoice table. -/
namespace Proofs
open Belay.Sqlite SqliteVerifier

/-- The resolved addition binds the exact default and NOT NULL metadata in the contract.
The proof reduces the sealed generated statement. -/
theorem script_bound : Generated.resolved = [.addColumn 0 Requirements.priority] := by rfl

/-- The resulting catalog is the starting catalog with the priority column appended.
The proof reduces the sealed generated catalogs. -/
theorem catalog_bound : Generated.nextCatalog =
    Generated.startCatalog.appendAt 0 [Requirements.priority] := by rfl

/-- The literal default reads as integer seven. The kernel computes the default reader. -/
theorem default_value : readDefaultValue Requirements.priority = .ok (.integer 7) := by rfl

/-- For every admitted starting database, the generated migration succeeds and
preserves every invoice rowid and amount under the exact resulting catalog.
The proof constructs a starting witness, obtains the invoice table from
conformance, computes ADD COLUMN, and uses the old-projection preservation lemma.
No starting row count or amount is assumed. -/
theorem migrationCorrect : Generated.expected := by
  have startValid : Generated.startCatalog.Valid Generated.profile.limits := by decide +kernel
  have nextValid : Generated.nextCatalog.Valid Generated.profile.limits := by decide +kernel
  apply VerificationConditions.of_runSql
  · exact ⟨Generated.startCatalog.emptyDatabase, Catalog.emptyDatabase_conforms startValid, trivial⟩
  · exact projectedInterpretation_sound Requirements.contract Generated.profile
      Generated.startCatalog "invoices" ["amount"] (by intros; trivial)
  · exact projectedInterpretation_sound Requirements.contract Generated.profile
      Generated.nextCatalog "invoices" ["amount"] (by intros; trivial)
  · exact unreachableFailures_sound Requirements.contract Generated.profile
  · intro database admitted
    obtain ⟨table, present, shape, valid⟩ := admitted.1.table (position := 0) (by rfl)
    exact ⟨admitted.1, 0, table, by decide +kernel, present, fun name member => by
      simp only [List.mem_singleton] at member
      subst name
      exact ⟨0, by rw [shape]; decide +kernel⟩⟩
  · intro database _
    exact supportedSqlFrom_schemaOnly (by simp [SchemaOnly, script_bound])
      (by simp [ModeledDefinitions, script_bound, default_value, Except.toOption])
  · intro database admitted
    obtain ⟨table, present, shape, valid⟩ := admitted.1.table (position := 0) (by rfl)
    let extended := table.appendColumns [(Requirements.priority, .integer 7)]
    have conforms : Conforms Generated.profile Generated.nextCatalog (database.set 0 extended) := by
      rw [catalog_bound]
      exact admitted.1.appendAt (columns := [(Requirements.priority, .integer 7)]) present
        (catalog_bound ▸ nextValid)
    have executed : runSql Generated.resolved database = .success (database.set 0 extended) := by
      simp [runSql, runSqlFrom, advance, literalStep, SqlState.finish, script_bound, step,
        present, default_value, extended]
    rw [executed]
    refine ⟨trivial, ?_⟩
    intro original originalRead
    have covered : Covers table ["amount"] := by
      intro name member
      simp only [List.mem_singleton] at member
      subst name
      exact ⟨0, by rw [shape]; decide +kernel⟩
    have growth : TableExtends table extended := ⟨[(Requirements.priority, .integer 7)], rfl⟩
    have sameProjection := growth.project (fun row member => (valid.2 row member).2.1) covered
    have stored : (database.set 0 extended) 0 = some extended := by simp [Database.set]
    refine ⟨⟨conforms, 0, extended, by decide +kernel, stored, growth.covers covered⟩,
      by change Generated.nextCatalog.columnsOf "invoices" = some [Requirements.amount, Requirements.priority]; decide +kernel, table.project ["amount"], ?_, ?_⟩
    · have located : tablePosition Generated.nextCatalog "invoices" = some 0 := by decide +kernel
      simpa [NextInterpretation.next, projectedInterpretation, observeTable, located, stored] using
        congrArg some sameProjection
    · have located : tablePosition Generated.startCatalog "invoices" = some 0 := by decide +kernel
      simpa [Interpretation.current, projectedInterpretation, observeTable, located, present,
        Requirements.contract] using originalRead.symm

#print axioms migrationCorrect
end Proofs
