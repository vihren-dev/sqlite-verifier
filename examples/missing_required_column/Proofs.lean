import Generated

/-! A checked refutation identifies the unfulfilled standing schema requirement. -/
namespace Proofs

/-- The required invoice.note column is absent from the generated result schema. -/
theorem migrationViolated : ¬Generated.expected := by
  apply SqliteVerifier.violates_required_schema (successRequired := rfl)
  change ¬(some [({ name := "amount", affinity := .integer } : SqliteVerifier.Column)] =
    some [({ name := "amount", affinity := .integer } : SqliteVerifier.Column), { name := "note", affinity := .text }])
  decide

end Proofs
