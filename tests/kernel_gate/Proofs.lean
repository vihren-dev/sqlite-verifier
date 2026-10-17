import Generated

set_option doc.verso true

/-! A real closed proof exercises replay against the formal model. -/
open Belay.Sqlite SqliteVerifier
namespace Proofs
/-- The fixture's observation covers every admitted empty-catalog database. -/
theorem sound : SoundRepresentation Requirements.contract Generated.profile [] Interpretation.current := by
  intro database conforms
  exact ⟨conforms, (), rfl, True.intro⟩
/-- The complete {name}`Generated.expected` target holds for this empty script.
The proof provides an admitted witness, sound representations, explicit SQL support
and the computed successful outcome at every clock assignment, because the script reads no
clock; no extra execution premise is assumed. -/
theorem migrationCorrect : Generated.expected := by
  apply VerificationConditions.of_runSql
  · exact ⟨Catalog.emptyDatabase [], Catalog.emptyDatabase_conforms (by decide), trivial⟩
  · exact sound
  · exact sound
  · intro position reason
    exact sound
  · intro database admitted
    exact admitted.1
  · intro database _ _
    rfl
  · intro database admitted
    constructor
    · trivial
    · intro original observed
      exact ⟨admitted.1, True.intro, (), rfl, True.intro⟩
  · rfl
end Proofs
