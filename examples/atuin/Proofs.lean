import Generated
import AtuinFacts
import AtuinWitness
import HistoryDecodingChecks

/-! A closed preservation certificate for the supplied SQL over every admitted
business history. Success and complete decoding are proved, not assumed. -/
namespace Proofs
open SqliteVerifier

/-- Complete decoding establishes valid business objects for any represented schema. -/
theorem mapping (schema : Schema) :
    SoundRepresentation Requirements.contract schema
      ⟨HistoryMapping.representation schema, HistoryMapping.observe⟩ := by
  intro database invariant
  obtain ⟨conforms, histories, observed⟩ := invariant
  exact ⟨conforms, histories, observed, HistoryMapping.observe_valid observed⟩

/-- Every modeled outcome is successful and preserves the complete old business state. -/
theorem migrationCorrect : Generated.expected := by
  refine ⟨⟨_, AtuinWitness.populated_admitted⟩, mapping _, mapping _,
    unreachableFailures_sound Requirements.contract, ?_, ?_, ?_⟩
  · intro database admitted
    exact admitted
  · intro database admitted
    exact ⟨by decide +kernel, supportedSqlFrom_extensions (by decide +kernel)⟩
  · intro database admitted outcome execution
    obtain ⟨history, present, columns, valid, executed, conforms⟩ := AtuinFacts.payload admitted.1
    have same : run Generated.script database = outcome :=
      (runSqlFrom_extensions (by decide +kernel)).symm.trans execution.result
    rw [executed] at same
    subst outcome
    refine ⟨True.intro, ?_⟩
    intro original read
    have after := AtuinFacts.observed present columns valid read
    exact ⟨⟨conforms, original, after⟩, True.intro, original, after, rfl⟩

#print axioms migrationCorrect
end Proofs
