import Generated
import AtuinOutcomes
import AtuinTraces

/-! The seven-input certificate covers every admitted history, not selected test rows. -/
namespace Proofs
open SqliteVerifier

/-- The unchanged upstream payload meets the approved projection for every runner outcome. -/
theorem migrationCorrect : Generated.expected := by
  refine ⟨⟨_, AtuinWitness.populated_admitted⟩, AtuinFacts.current_sound,
    AtuinFacts.next_sound, AtuinFacts.failures_sound, fun _ admitted => admitted.1,
    fun _ admitted => admitted.2, ?_⟩
  intro database admitted outcome execution
  exact AtuinOutcomes.all admitted execution

#print axioms migrationCorrect
end Proofs
