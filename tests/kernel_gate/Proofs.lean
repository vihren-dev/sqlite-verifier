import Generated

set_option doc.verso true

/-! A real closed proof exercises replay against the formal model. -/
open Belay.Sqlite SqliteVerifier
namespace Proofs
/-- The fixture's observation covers every admitted empty-schema database. -/
theorem sound : SoundRepresentation Requirements.contract [] Interpretation.current := by
  intro database conforms
  exact ⟨conforms, (), rfl, True.intro⟩
/-- The complete {name}`Generated.expected` target holds for this empty script.
The proof provides an admitted witness, sound representations, explicit SQL support
and the computed successful outcome; no extra execution premise is assumed. -/
theorem migrationCorrect : Generated.expected := by
  apply VerificationConditions.of_runSql
  · exact ⟨fun _ => none, by
      simp [Admitted, Conforms, Schema.Valid, Schema.lookupShape,
        Generated.startSchema, Interpretation.admitted]⟩
  · exact sound
  · exact sound
  · intro position reason
    exact sound
  · intro database admitted
    exact admitted.1
  · intro database _
    exact ⟨by decide +kernel, by rfl⟩
  · intro database admitted
    constructor
    · trivial
    · intro original observed
      exact ⟨admitted.1, True.intro, (), rfl, True.intro⟩
end Proofs
