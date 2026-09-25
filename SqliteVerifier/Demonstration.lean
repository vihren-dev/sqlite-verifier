import SqliteVerifier.Library

/-! Engineering example: arbitrary stored amounts survive a column addition and
new table. This is a complete VC proof, not a real-pilot acceptance claim. -/

namespace SqliteVerifier.Demonstration

/-- The field whose values and row identities are protected by the requirements. -/
def amount : Column := { name := "amount", affinity := .integer }
/-- Nullable annotation introduced by the candidate migration. -/
def note : Column := { name := "note", affinity := .text }
/-- New table's unprotected field. -/
def message : Column := { name := "message", affinity := .text }
/-- Accepted current schema; rows remain universally quantified. -/
def startSchema : Schema := [{ name := "invoices", columns := [amount] }]
/-- Schema of the committed prefix after its first successful statement. -/
def middleSchema : Schema := [{ name := "invoices", columns := [amount, note] }]
/-- The proposed resulting schema includes an independent empty audit table. -/
def nextSchema : Schema := [{ name := "invoices", columns := [amount, note] }, { name := "audit", columns := [message] }]
/-- Two statements show ordering rather than assuming file-level atomicity. -/
def script : List Statement :=
  [.addColumn "invoices" note, .createTable "audit" [message]]
/-- The same contract can be reused with independently checked additive scripts. -/
def requirements : LogicalContract LogicalRows where
  valid := fun _ => True
  change := Eq
  schemaRequirement schema := schema.lookup "invoices" = some [amount, note]
  failure := fun before _ _ after => before = after
  applicability := requiresSuccess
/-- Current meaning includes every stored invoice and its actual amount. -/
def current : Interpretation LogicalRows := projectedInterpretation startSchema "invoices" ["amount"]
/-- Resulting meaning reads the same protected projection from resulting storage. -/
def next : Interpretation LogicalRows := projectedInterpretation nextSchema "invoices" ["amount"]

/-- The schema constraints themselves admit the empty database witness. -/
theorem start_valid : startSchema.Valid := by
  simp [Schema.Valid, startSchema]
  decide +kernel
/-- The intermediate schema stays inside the documented subset. -/
theorem middle_valid : middleSchema.Valid := by
  simp [Schema.Valid, middleSchema]
  decide +kernel
/-- The second table is distinct and has an admitted definition. -/
theorem next_valid : nextSchema.Valid := by
  simp [Schema.Valid, nextSchema]
  decide +kernel

/-- Entire generated obligations are proved for arbitrary admissible initial rows. -/
theorem migrationCorrect :
    VerificationConditions startSchema nextSchema script (fun _ => True)
      requirements current next unreachableFailures := by
  apply VerificationConditions.of_run
  · exact ⟨startSchema.emptyDatabase, startSchema.emptyDatabase_conforms start_valid, trivial⟩
  · exact projectedInterpretation_sound requirements startSchema "invoices" ["amount"]
      (by intros; trivial)
  · exact projectedInterpretation_sound requirements nextSchema "invoices" ["amount"]
      (by intros; trivial)
  · exact unreachableFailures_sound requirements
  · intro database admitted
    obtain ⟨table, present, columns, _⟩ := admitted.1.table (name := "invoices") (by rfl)
    refine ⟨admitted.1, table, present, ?_⟩
    intro name member
    simp only [List.mem_singleton] at member
    subst name
    exact ⟨0, by simp [columns, amount]⟩
  · intro database admitted
    obtain ⟨table, present, columns, valid⟩ := admitted.1.table (name := "invoices") (by rfl)
    have absent : database "audit" = none := by
      have shape := (admitted.1.2 "audit").1
      simpa [Schema.lookup, startSchema] using shape
    have supported : supportedColumns (table.columns ++ [note]) = true := by
      rw [columns]
      decide +kernel
    have properties : table.properties = {} := by
      have stored := ((admitted.1.2 "invoices").2 table present).2
      simpa [Schema.lookupProperties, startSchema] using stored.symm
    have middleConforms : Conforms middleSchema (database.set "invoices" (table.appendColumns [note])) :=
      admitted.1.set middle_valid (valid.appendColumns supported) (by
        intro other
        by_cases same : other = "invoices"
        · subst other; simp [Schema.lookup, middleSchema, Table.appendColumns, columns]
        · simp [Schema.lookup, List.find?, startSchema, middleSchema, same, Ne.symm same]) (by
        intro other
        by_cases same : other = "invoices" <;>
          simp [Schema.lookupProperties, List.find?, startSchema, middleSchema,
            Table.appendColumns, properties, same, Ne.symm])
    have finalConforms : Conforms nextSchema
        ((database.set "invoices" (table.appendColumns [note])).set "audit" { columns := [message], rows := [] }) :=
      middleConforms.set next_valid (by exact ⟨by decide +kernel, by simp, by simp⟩) (by
        intro other
        by_cases audit : other = "audit"
        · subst other; simp [Schema.lookup, List.find?, nextSchema]
        · by_cases invoices : other = "invoices"
          · subst other; simp [Schema.lookup, middleSchema, nextSchema]
          · have auditFalse : ("audit" == other) = false := beq_eq_false_iff_ne.mpr (Ne.symm audit)
            simp [Schema.lookup, List.find?, middleSchema, nextSchema,
              audit, auditFalse, Ne.symm invoices]) (by
        intro other
        by_cases audit : other = "audit"
        · subst other; simp [Schema.lookupProperties, nextSchema]
        · by_cases invoices : other = "invoices"
          · subst other; simp [Schema.lookupProperties, middleSchema, nextSchema]
          · have auditFalse : ("audit" == other) = false := beq_eq_false_iff_ne.mpr (Ne.symm audit)
            simp [Schema.lookupProperties, List.find?, middleSchema, nextSchema,
              audit, auditFalse, Ne.symm invoices])
    have executed : run script database = .success
        ((database.set "invoices" (table.appendColumns [note])).set "audit" { columns := [message], rows := [] }) := by
      have invoiceName : supportedTableName "invoices" = true := by decide +kernel
      have noteSupported : supportedColumn note = true := by decide +kernel
      have notePlain : note.plain = true := by decide +kernel
      have auditName : supportedTableName "audit" = true := by decide +kernel
      have auditColumns : supportedColumns [message] = true := by decide +kernel
      have messagePlain : message.plain = true := by decide +kernel
      have noDuplicate : table.columns.any (fun old => old.name == note.name) = false := by
        rw [columns]; decide +kernel
      have belowLimit : table.columns.length < maximumColumns := by rw [columns]; decide
      simp [run, runFrom, script, step, present, absent, Database.set,
        invoiceName, noteSupported, auditName, auditColumns, messagePlain, notePlain, noDuplicate, Nat.not_le.mpr belowLimit]
    rw [executed]
    refine ⟨trivial, ?_⟩
    intro original originalRead
    have covered : Covers table ["amount"] := by
      intro name member
      simp only [List.mem_singleton] at member
      subst name
      exact ⟨0, by simp [columns, amount]⟩
    have growth : TableExtends table (table.appendColumns [note]) := ⟨[note], rfl⟩
    have sameProjection := growth.project (fun row member => (valid.2.2 row member).2) covered
    refine ⟨⟨finalConforms, table.appendColumns [note], by simp [Database.set], growth.covers covered⟩,
      by rfl, table.project ["amount"], ?_, ?_⟩
    · simpa [next, projectedInterpretation, observeTable, Database.set] using congrArg some sameProjection
    · simpa [current, projectedInterpretation, observeTable, present, requirements] using originalRead.symm

#print axioms migrationCorrect

end SqliteVerifier.Demonstration
