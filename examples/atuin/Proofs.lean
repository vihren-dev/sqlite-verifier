import Generated
import AtuinOutcomes
import AtuinSound
import AtuinWitness
import HistoryDecodingChecks

/-! A closed certificate for the supplied SQL over every admitted decoded history. -/
namespace Proofs
open SqliteVerifier

/-- The complete explicit transaction preserves business history and establishes the new representation. -/
theorem migrationCorrect : Generated.expected := by
  refine ⟨⟨_, AtuinWitness.populated_admitted⟩, AtuinSound.current,
    AtuinSound.next, AtuinSound.failures, ?_, ?_, ?_⟩
  · intro database admitted
    obtain ⟨defined, metadata, stored, invariant, _⟩ := admitted.2
    exact ⟨admitted.1, defined, metadata, stored, invariant⟩
  · intro database admitted
    exact (AtuinOutcomes.checked database admitted).1
  · intro database admitted outcome execution
    rw [← execution.result]
    exact (AtuinOutcomes.checked database admitted).2

#print axioms migrationCorrect
end Proofs
