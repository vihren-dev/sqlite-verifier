import Generated
import AtuinFacts
import AtuinWitness
import HistoryDecodingChecks

set_option doc.verso true

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

/-- The complete generated verification target holds for every admitted business
history. The proof provides a populated starting witness, sound decoding, support
and direct SQL execution. The successful ADD retains the entire old history
projection; no execution outcome is excluded through an extra premise. -/
theorem migrationCorrect : Generated.expected := by
  refine ⟨⟨_, AtuinWitness.populated_admitted⟩, mapping _, mapping _,
    unreachableFailures_sound Requirements.contract, ?_, ?_, ?_⟩
  · intro database admitted
    exact admitted
  · intro database admitted
    exact ⟨by decide +kernel, supportedSqlFrom_schemaOnly (by simp [SchemaOnly, AtuinFacts.script_bound])⟩
  · intro database admitted outcome execution
    obtain ⟨history, present, columns, valid, executed, conforms⟩ := AtuinFacts.payload admitted.1
    have same : runSql Generated.script database = outcome := execution.result
    rw [executed] at same
    subst outcome
    refine ⟨True.intro, ?_⟩
    intro original read
    have after := AtuinFacts.observed present columns valid read
    exact ⟨⟨conforms, original, after⟩, True.intro, original, after, rfl⟩

#print axioms migrationCorrect
end Proofs
