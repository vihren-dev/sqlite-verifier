import Generated

/-! A checked refutation identifies the unfulfilled standing schema requirement. -/
namespace Proofs

/-- The required invoice.note column is absent from the generated result schema. -/
theorem migrationViolated : ¬Generated.expected := by
  apply SqliteVerifier.violates_required_schema (successRequired := rfl)
  change ¬(some [SqliteVerifier.Column.mk "amount" .integer] =
    some [SqliteVerifier.Column.mk "amount" .integer, ⟨"note", .text⟩])
  decide

end Proofs
