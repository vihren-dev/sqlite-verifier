import AtuinSql

/-! Universal guarantees concern decoded business histories, not storage-layout entities. -/
namespace AtuinOutcomes
open SqliteVerifier

/-- The NULL column extension leaves every complete business history unchanged. -/
theorem observed (present : database "history" = some history)
    (columns : history.columns = SchemaBinding.history.columns) (valid : history.Valid)
    (before : HistoryMapping.observe false database = some logical) :
    HistoryMapping.observe true (AtuinSql.result database history metadata) = some logical := by
  have decoded : HistoryDecoding.decodeRows (history.project SchemaBinding.fields) = some logical := by
    simpa [HistoryMapping.observe, present] using before
  have width := fun row member => (valid.2.2 row member).2
  have unchanged : (history.appendColumns [SchemaBinding.shell]).project SchemaBinding.fields =
      history.project SchemaBinding.fields :=
    TableExtends.project ⟨[SchemaBinding.shell], rfl⟩ width (AtuinFacts.covers columns)
  have shell : (history.appendColumns [SchemaBinding.shell]).project ["shell"] =
      nullExtension (history.project SchemaBinding.fields) :=
    Table.project_newNullable width (by rw [columns]; decide +kernel)
  simpa [HistoryMapping.observe, AtuinSql.history_stored, unchanged, shell, decoded] using
    HistoryDecoding.attachShell_null decoded

/-- Arbitrary admitted histories and prior catalog rows satisfy every reached statement and postcondition. -/
theorem checked (database : Database)
    (admitted : Admitted Generated.startSchema Interpretation.admitted database) :
    SupportedSql Generated.startSchema Generated.script database ∧
    Requirements.contract.applicability database (runSql Generated.script database) ∧
    OutcomeSatisfies Generated.nextSchema Requirements.contract Interpretation.current
      NextInterpretation.next NextInterpretation.failures database (runSql Generated.script database) := by
  obtain ⟨defined, metadata, metadataStored, invariant, bounded⟩ := admitted.2
  obtain ⟨history, historyStored, historyColumns, historyValid⟩ :=
    admitted.1.table (name := "history") (by rfl)
  have metadataColumns : metadata.columns = SchemaBinding.metadata.columns := by
    have shape := (admitted.1.2 "_sqlx_migrations").1
    rw [metadataStored] at shape
    change some metadata.columns = some SchemaBinding.metadata.columns at shape
    exact Option.some.inj shape
  have metadataProperties : metadata.properties = SchemaBinding.metadata.properties := by
    have shape := ((admitted.1.2 "_sqlx_migrations").2 metadata metadataStored).2
    change some SchemaBinding.metadata.properties = some metadata.properties at shape
    exact (Option.some.inj shape).symm
  have executed := AtuinSql.executes historyStored historyColumns metadataStored
    metadataColumns metadataProperties invariant bounded
  have finalConforms := AtuinSql.conforms admitted.1 historyStored metadataStored metadataColumns bounded
  have finalCatalog : HistoryMapping.catalog (AtuinCatalog.prior ++ [AtuinCatalog.target])
      (AtuinSql.result database history metadata) :=
    ⟨AtuinMetadata.extended metadata 1000000, AtuinSql.metadata_stored,
      AtuinMetadata.extended_invariant metadataColumns metadataProperties invariant⟩
  obtain ⟨logical, before⟩ := defined
  have after := observed (metadata := metadata) historyStored historyColumns historyValid before
  have representation : HistoryMapping.representation SchemaBinding.next true
      (AtuinCatalog.prior ++ [AtuinCatalog.target]) (AtuinSql.result database history metadata) :=
    ⟨finalConforms, ⟨logical, after⟩, finalCatalog⟩
  rw [AtuinSql.inputs_bound.1]
  refine ⟨executed.2, ?_⟩
  rw [executed.1]
  refine ⟨⟨representation, logical, before, after⟩, ?_⟩
  intro original read
  have same : original = logical := by
    change HistoryMapping.observe false database = some original at read
    rw [before] at read
    exact (Option.some.inj read).symm
  subst original
  exact ⟨by simpa [NextInterpretation.next, AtuinFacts.next_bound] using representation,
    AtuinFacts.next_bound, logical, after, rfl⟩

end AtuinOutcomes
