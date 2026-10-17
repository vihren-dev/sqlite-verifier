import Generated
import AtuinFacts
import AtuinWitness
import HistoryDecodingChecks

set_option doc.verso true

/-! A closed preservation certificate for the supplied SQL over every admitted
business history. Success and complete decoding are proved, not assumed. -/
namespace Proofs
open Belay.Sqlite SqliteVerifier

/-- Complete decoding establishes valid business objects for any represented
catalog under any profile. -/
theorem mapping (profile : Profile) (catalog : Catalog) :
    SoundRepresentation Requirements.contract profile catalog
      ⟨HistoryMapping.representation profile catalog, HistoryMapping.observe⟩ := by
  intro database invariant
  obtain ⟨conforms, histories, observed⟩ := invariant
  exact ⟨conforms, histories, observed, HistoryMapping.observe_valid observed⟩

/-- The complete generated verification target holds for every admitted business
history. The proof provides a populated starting witness, sound decoding, support
and direct SQL execution. The successful ADD retains the entire old history
projection; no execution outcome is excluded through an extra premise. -/
theorem migrationCorrect : Generated.expected := by
  refine ⟨⟨_, AtuinWitness.populated_admitted⟩, mapping _ _, mapping _ _,
    unreachableFailures_sound Requirements.contract _, ?_, ?_, ?_⟩
  · intro database admitted
    exact admitted
  · intro database admitted
    exact SupportedSql.schemaOnly (by simp [SchemaOnly, AtuinFacts.script_bound])
      (by simp [ModeledDefinitions, AtuinFacts.script_bound, AtuinFacts.added, CatalogColumn.plain, readDefaultValue, Except.toOption, CatalogColumn.clockDefault])
  · intro database admitted outcome execution
    obtain ⟨history, present, shape, valid, executed, conforms⟩ := AtuinFacts.payload admitted.1
    have same : runSql Generated.resolved database = outcome :=
      execution.result_of_readsClock (by simp [scriptReadsClock, AtuinFacts.script_bound, Resolved.Statement.readsClock])
    rw [executed] at same
    subst outcome
    refine ⟨True.intro, ?_⟩
    intro original read
    have after := AtuinFacts.observed present (by rw [shape]) valid read
    exact ⟨⟨conforms, original, after⟩, True.intro, original, after, rfl⟩

#print axioms migrationCorrect
end Proofs
