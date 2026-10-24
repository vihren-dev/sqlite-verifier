import Belay.Sqlite.Model.ResolveFinishShaped
import Belay.Sqlite.Model.CatalogTableLaws

set_option doc.verso true

/-! The table that CREATE TABLE builds is supported (ADR 0022, D3, slice 4): the facts of
{lit}`CatalogTable.SupportedFacts` hold for the table after the options of the table, the CHECK
constraints and the generated columns. -/

namespace Belay.Sqlite.Model

/-- For every table, {name}`CatalogTable.asWithoutRowid` of the table has the layouts of the columns of
the table. Proof sketch: it changes only the NOT NULL flag of columns. -/
theorem CatalogTable.asWithoutRowid_layouts (table : CatalogTable) :
    table.asWithoutRowid.columns.map CatalogColumn.layout = table.columns.map CatalogColumn.layout :=
  map_mapIdx _ _ _ fun position column => by split <;> rfl

/-- For every table, {name}`CatalogTable.withStrictKeys` of the table has the layouts of the columns of
the table. Proof sketch: it changes only the NOT NULL flag of columns. -/
theorem CatalogTable.withStrictKeys_layouts (table : CatalogTable) :
    table.withStrictKeys.columns.map CatalogColumn.layout = table.columns.map CatalogColumn.layout := by
  unfold CatalogTable.withStrictKeys
  split
  · rfl
  · exact map_mapIdx _ _ _ fun position column => by split <;> rfl

/-- For every draft table, {name}`CatalogTable.asWithoutRowid` of the table satisfies
{name}`CatalogTable.Shaped`. Proof sketch: the layouts of the columns stay, the primary key loses
its repeated positions, and the rowid alias is none. -/
theorem CatalogTable.asWithoutRowid_shaped {table : CatalogTable} (draft : table.Draft) :
    table.asWithoutRowid.Shaped := by
  have layouts := table.asWithoutRowid_layouts
  have length : table.asWithoutRowid.columns.length = table.columns.length := by
    simpa using congrArg List.length layouts
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro position member
    rw [length]
    exact draft.shaped.primaryKey position (List.mem_eraseDups.mp member)
  · rw [length]; exact draft.shaped.uniqueKeys
  · rw [folded_eq_of_names (names_eq_of_layout layouts)]; exact draft.shaped.names
  · intro position found; cases found

/-- For every draft table, {name}`CatalogTable.withStrictKeys` of the table satisfies
{name}`CatalogTable.Shaped`, and it has the rowid kind and the rowid alias of the table. Proof sketch:
only the NOT NULL flag of columns changes, which the layouts do not read. -/
theorem CatalogTable.withStrictKeys_shaped {table : CatalogTable} (draft : table.Draft) :
    table.withStrictKeys.Shaped ∧ table.withStrictKeys.withoutRowid = table.withoutRowid ∧
      table.withStrictKeys.rowidAlias = table.rowidAlias := by
  refine ⟨draft.shaped.of_layout table.withStrictKeys_layouts ?_ ?_ ?_, ?_, ?_⟩ <;>
    (unfold CatalogTable.withStrictKeys; split <;> rfl)

/-- For every name, columns and rowid flag, the scope of one table ends below the number of its columns ({name}`Scope.Bounded`). Proof sketch: the only source has offset zero.  -/
theorem Scope.single_bounded (name : Identifier) (columns : List CatalogColumn) (hasRowid : Bool) :
    (Scope.single name columns hasRowid).Bounded columns.length := by
  intro source member
  simp only [Scope.single, List.mem_singleton] at member
  subst member
  simp

/-- For every table that satisfies {name}`CatalogTable.Shaped`, has no rowid alias in a WITHOUT ROWID
table, has the names of the definitions, at most as many columns as the limit, and a column that is not
generated: if the CHECK constraints and then the generated columns resolve to the table {lit}`third`,
and no definition has the name of the rowid, the table {lit}`third` is supported
({name}`CatalogTable.supported`). Proof sketch: the layouts, the keys and the alias stay
({name}`resolveTableChecks_keeps`, {name}`resolveGeneratedColumns_keeps`), so only the CHECK
constraints are new, and these read below the number of columns ({name}`resolveTableChecks_below`). -/
theorem CatalogTable.supported_of_finished {limits : Limits} {dqs : Bool} {name : Identifier}
    {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint}
    {first second third : CatalogTable} (shaped : first.Shaped)
    (aliasKind : first.rowidAlias.isSome = true → first.withoutRowid = false)
    (named : first.columns.map (·.name) = definitions.map (·.name))
    (within : first.columns.length ≤ limits.columns)
    (notGenerated : ¬(first.columns.all fun column => column.generated.isSome) = true)
    (ordinaryNames : (definitions.any fun definition => rowidName definition.name) = false)
    (checked : resolveTableChecks dqs (Scope.single name first.columns !first.withoutRowid) first definitions
      constraints = .ok second)
    (generated : resolveGeneratedColumns dqs (Scope.single name second.columns false) second definitions =
      .ok third) :
    third.supported limits = true := by
  have equal : first.columns.length = definitions.length := by simpa using congrArg List.length named
  obtain ⟨layout2, pk2, uk2, alias2, wr2⟩ := resolveTableChecks_keeps equal checked
  have equal2 : second.columns.length = definitions.length := by
    simpa [equal] using congrArg List.length layout2
  obtain ⟨layout3, checks3, tableChecks3, pk3, uk3, alias3, wr3⟩ := resolveGeneratedColumns_keeps equal2 generated
  have layouts : third.columns.map CatalogColumn.layout = first.columns.map CatalogColumn.layout :=
    layout3.trans layout2
  have length : third.columns.length = first.columns.length := by simpa using congrArg List.length layouts
  have names : third.columns.map (·.name) = definitions.map (·.name) := (names_eq_of_layout layouts).trans named
  have below := resolveTableChecks_below (Scope.single_bounded name first.columns _) (by
    rw [List.drop_of_length_le (by omega)]; simp) checked
  refine (CatalogTable.supported_iff limits third).mpr ⟨?_, by omega, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · intro empty
    rw [empty] at length
    cases hfirst : first.columns with
    | nil => simp [hfirst] at notGenerated
    | cons head tail => simp [hfirst] at length
  · rw [folded_eq_of_names (names_eq_of_layout layouts)]; exact shaped.names
  · intro column member
    have inNames : column.name ∈ definitions.map (·.name) := by
      rw [← names]; exact List.mem_map_of_mem member
    obtain ⟨definition, inDefinitions, same⟩ := List.mem_map.mp inNames
    rw [← same]
    simpa using List.any_eq_false.mp ordinaryNames definition inDefinitions
  · intro position member
    rw [length, pk3, pk2] at *
    exact shaped.primaryKey position member
  · rw [length, uk3, uk2] at *
    exact shaped.uniqueKeys
  · intro position found
    rw [alias3, alias2] at found
    obtain ⟨key, aliased⟩ := shaped.alias position found
    obtain ⟨column, atPosition, noGenerated, integer⟩ := aliased.of_layout layouts
    exact ⟨pk3.trans (pk2.trans key), (wr3.trans wr2).trans (aliasKind (by rw [found]; rfl)),
      column, atPosition, noGenerated, integer⟩
  · have columnChecks : third.columns.flatMap (·.checks) = second.columns.flatMap (·.checks) := by
      rw [List.flatMap_def, List.flatMap_def, checks3]
    intro check member
    have : check ∈ second.allChecks := by
      simp only [CatalogTable.allChecks, List.mem_append, columnChecks, tableChecks3] at member ⊢
      exact member
    simpa [Resolved.Expr.readsBelow, length] using below check this

end Belay.Sqlite.Model
