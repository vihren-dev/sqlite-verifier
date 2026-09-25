import AtuinFacts

/-! Mapping validity is derived from complete decoding, not assumed of a candidate reader. -/
namespace AtuinSound
open SqliteVerifier

/-- The common approved mapping exposes actual valid business objects and the exact schema. -/
theorem mapping (schema : Schema) (shell : Bool) (catalog : List AtuinCatalog.Identity) :
    SoundRepresentation Requirements.contract schema
      ⟨HistoryMapping.representation schema shell catalog, HistoryMapping.observe shell⟩ := by
  intro database invariant
  obtain ⟨conforms, ⟨histories, observed⟩, _⟩ := invariant
  exact ⟨conforms, histories, observed, HistoryMapping.observe_valid observed⟩

/-- The schema-pinned current interpretation is sound for every represented database. -/
theorem current : SoundRepresentation Requirements.contract Generated.startSchema Interpretation.current :=
  mapping _ _ _
/-- The resulting interpretation decodes real shell values for every represented database. -/
theorem next : SoundRepresentation Requirements.contract Generated.nextSchema NextInterpretation.next :=
  mapping _ _ _
/-- No failure representation is assumed inhabited; successful execution is proved separately. -/
theorem failures (position reason) : SoundRepresentation Requirements.contract
    (NextInterpretation.failures.schema position reason)
    (NextInterpretation.failures.interpretation position reason) :=
  unreachableFailures_sound Requirements.contract position reason

end AtuinSound
