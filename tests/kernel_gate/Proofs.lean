import Generated

/-! A real closed proof exercises replay against the formal model. -/
open SqliteVerifier
namespace Proofs
/-- The fixture's observation covers every admitted empty-schema database. -/
theorem sound : SoundRepresentation Requirements.contract [] Interpretation.current := by
  intro database conforms
  exact ⟨conforms, (), rfl, True.intro⟩
/-- The empty script establishes all six required obligations. -/
theorem migrationCorrect : Generated.expected := by
  apply VerificationConditions.of_run (by decide +kernel) (by decide +kernel)
  · exact ⟨fun _ => none, by
      simp [Admitted, Conforms, Schema.Valid, Schema.lookup,
        Generated.startSchema, Interpretation.admitted]⟩
  · exact sound
  · exact sound
  · intro position reason
    exact sound
  · intro database admitted
    exact admitted.1
  · intro database admitted
    constructor
    · trivial
    · intro original observed
      exact ⟨admitted.1, True.intro, (), rfl, True.intro⟩
end Proofs
