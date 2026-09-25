import AtuinMetadata

/-! Both explicit bookkeeping writes preserve arbitrary accepted old rows. -/
namespace AtuinWrites
open SqliteVerifier AtuinMetadata

/-- The supplied INSERT lies inside the generic lossless-literal domain. -/
theorem insert_ready (columns : table.columns = SchemaBinding.metadata.columns)
    (properties : table.properties = SchemaBinding.metadata.properties)
    (invariant : AtuinCatalog.Invariant AtuinCatalog.prior table)
    (bounded : validRowid (LiteralData.nextRowid table.rows)) :
    LiteralData.insertReady table (SchemaBinding.metadata.columns.map Column.name) (values (-1)) = true := by
  have rowid : LiteralData.boundedInteger (LiteralData.nextRowid table.rows) = true := by
    simpa [LiteralData.boundedInteger, validRowid] using bounded
  simp only [LiteralData.insertReady, properties, invariant.1, rowid, LiteralData.read, columns]
  decide +kernel

/-- Updating the unique new version changes its duration and leaves every old row intact. -/
theorem updated (columns : table.columns = SchemaBinding.metadata.columns)
    (recorded : AtuinCatalog.recorded AtuinCatalog.prior table.rows) :
    LiteralData.updated (extended table (-1)) "execution_time" (.integer 1000000)
      "version" AtuinCatalog.targetVersion = extended table 1000000 := by
  have find : (extended table (-1)).columns.findIdx? (fun item => item.name == "execution_time") =
      some 5 := by change table.columns.findIdx? _ = some 5; rw [columns]; rfl
  have old : table.rows.map (fun row =>
      if LiteralData.matchesKey (extended table (-1)) row "version" AtuinCatalog.targetVersion
      then {row with values := row.values.set 5 (.integer 1000000)} else row) = table.rows := by
    suffices equal : table.rows.map (fun row =>
        if LiteralData.matchesKey (extended table (-1)) row "version" AtuinCatalog.targetVersion
        then {row with values := row.values.set 5 (.integer 1000000)} else row) = table.rows.map id by
      simpa using equal
    apply List.map_congr_left
    intro row member
    have absent := target_absent columns recorded row member
    have noMatch : LiteralData.matchesKey (extended table (-1)) row "version"
        AtuinCatalog.targetVersion = false := by
      simpa [LiteralData.matchesKey, LiteralData.read, extended, LiteralData.inserted] using absent
    simp [noMatch]
  simp only [LiteralData.updated, find]
  change { table with rows := (table.rows ++ [(⟨LiteralData.nextRowid table.rows, values (-1)⟩ : Row)]).map _ } = _
  rw [List.map_append, old]
  have matchNew : LiteralData.matchesKey (extended table (-1))
      ⟨LiteralData.nextRowid table.rows, values (-1)⟩ "version" AtuinCatalog.targetVersion = true := by
    simp only [LiteralData.matchesKey, new_version (show (extended table (-1)).columns =
      SchemaBinding.metadata.columns from columns), beq_self_eq_true]
  simp only [List.map_cons, List.map_nil, matchNew, ↓reduceIte]
  rfl

/-- The UPDATE predicate and assigned literal have checked generic comparison support. -/
theorem update_ready (columns : table.columns = SchemaBinding.metadata.columns)
    (properties : table.properties = SchemaBinding.metadata.properties)
    (invariant : AtuinCatalog.Invariant AtuinCatalog.prior table) :
    LiteralData.updateReady (extended table (-1)) "execution_time" (.integer 1000000)
      "version" AtuinCatalog.targetVersion = true := by
  have before := (extended_invariant (elapsed := -1) columns properties invariant).1
  have after := (extended_invariant (elapsed := 1000000) columns properties invariant).1
  have keys : table.properties.keys = [["version"]] := by rw [properties]; rfl
  have comparison : LiteralData.comparisonReady (extended table (-1)) "version" = true := by
    have both := before
    simp only [LiteralData.tableReady, Bool.and_eq_true] at both
    simpa only [extended, LiteralData.inserted, keys, List.all_cons, List.all_nil,
      Bool.and_true] using both.1
  simp only [LiteralData.updateReady, before, comparison, updated columns invariant.2]
  have afterKeys := after
  simp only [LiteralData.tableReady, Bool.and_eq_true] at afterKeys
  rw [afterKeys.1]
  simp only [extended, LiteralData.inserted, properties, columns]
  decide +kernel

end AtuinWrites
