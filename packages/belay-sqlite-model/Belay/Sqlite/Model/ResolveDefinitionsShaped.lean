import Belay.Sqlite.Model.ResolveConstraintShaped

set_option doc.verso true

/-! The column definitions of CREATE TABLE keep the invariant of the table (ADR 0022, D3, slice 4):
each definition adds one column and applies its constraints, so a draft stays a draft, the number of
columns stays within the limit, and the names are the names of the definitions. -/

namespace Belay.Sqlite.Model

/-- For every draft table, definition and name that is not the name of a column of the table: the
table with the defined column added is building the column. Proof sketch: the new column has a name
that no other column has, the keys and the alias columns keep their positions, and a strict ANY
column has the declared type ANY because the strict type is read from that type. -/
theorem CatalogTable.Building.defined {table : CatalogTable} (draft : table.Draft)
    (definition : Syntax.ColumnDefinition) (fresh : (columnPosition table.columns definition.name).isNone = true) :
    ({ table with columns := table.columns ++ [definedColumn table.strict definition] } : CatalogTable).Building
      definition := by
  obtain ⟨shaped, ordinary, declared⟩ := draft
  have absent := (findPosition_eq_none_iff _ _).mp (by simpa [columnPosition] using fresh)
  refine ⟨⟨⟨?_, ?_, ?_, ?_⟩, ordinary, ?_⟩, by simp [definedColumn]⟩
  · intro position member
    have := shaped.primaryKey position member
    simp only [List.length_append, List.length_singleton]; omega
  · intro key member
    obtain ⟨nonempty, below⟩ := shaped.uniqueKeys key member
    exact ⟨nonempty, fun position inside => by
      have := below position inside
      simp only [List.length_append, List.length_singleton]; omega⟩
  · simp only [List.map_append, List.map_cons, List.map_nil, List.nodup_append, List.nodup_cons, List.not_mem_nil]
    refine ⟨shaped.names, by simp, ?_⟩
    intro name inOld other inNew
    simp only [List.mem_singleton] at inNew
    subst inNew
    obtain ⟨column, inColumns, rfl⟩ := List.mem_map.mp inOld
    have := absent column inColumns
    simp only [Identifier.sameName, beq_eq_false_iff_ne, ne_eq] at this
    simpa [definedColumn] using this
  · intro position found
    obtain ⟨key, column, at_position, rest⟩ := shaped.alias position found
    refine ⟨key, column, ?_, rest⟩
    exact (List.getElem?_append_left (List.getElem?_eq_some_iff.mp at_position).1).trans at_position
  · intro column member strict
    rcases List.mem_append.mp member with old | new
    · exact declared column old strict
    · simp only [List.mem_singleton] at new
      subst new
      simp only [definedColumn] at strict ⊢
      split at strict
      · exact eq_any_of_ofReported strict
      · cases strict

/-- For every limit, table name, draft table that has at most as many columns as the limit and list of
definitions: if {name}`addDefinitions` gives a table, the table is a draft with at most as many columns
as the limit, the names of the columns of the table followed by the names of the definitions, and the
strictness of the table. Proof sketch: induction over the definitions; one definition adds a column
({name}`CatalogTable.Building.defined`), its constraints keep the building
({name}`applyConstraint_step`, by {name}`foldlM_except_invariant`), and the check of the limit keeps
the number of columns within it. -/
theorem addDefinitions_draft {limit : Nat} {tableName : Identifier} :
    ∀ {definitions : List Syntax.ColumnDefinition} {table result : CatalogTable}, table.Draft →
      table.columns.length ≤ limit → addDefinitions limit tableName table definitions = .ok result →
      result.Draft ∧ result.columns.length ≤ limit ∧
        result.columns.map (·.name) = table.columns.map (·.name) ++ definitions.map (·.name) ∧
        result.strict = table.strict
  | [], table, result, draft, within, ok => by
    cases ok
    exact ⟨draft, within, by simp, rfl⟩
  | definition :: rest, table, result, draft, within, ok => by
    unfold addDefinitions at ok
    split at ok
    all_goals split at ok
    all_goals first | (cases ok; done) | skip
    rename_i fresh fits
    simp only [exceptBind_eq_ok] at ok
    obtain ⟨constrained, folded, next⟩ := ok
    have building := CatalogTable.Building.defined draft definition (by simpa using fresh)
    generalize hadded : ({ table with columns := table.columns ++ [definedColumn table.strict definition] } :
      CatalogTable) = added at folded building
    have kept := foldlM_except_invariant (applyConstraint tableName definition)
      (fun table => table.Building definition ∧ table.columns.map (·.name) = added.columns.map (·.name) ∧
        table.strict = added.strict)
      (fun _ _ _ before step => by
        have next := applyConstraint_step before.1 _ step
        exact ⟨next.1, next.2.1.trans before.2.1, next.2.2.trans before.2.2⟩)
      definition.constraints added constrained ⟨building, rfl, rfl⟩ folded
    obtain ⟨builds, names, strict⟩ := kept
    have length : constrained.columns.length = table.columns.length + 1 := by
      have := congrArg List.length names
      subst hadded
      simpa using this
    obtain ⟨draft', within', names', strict'⟩ := addDefinitions_draft builds.1 (by omega) next
    refine ⟨draft', within', ?_, strict'.trans (strict.trans (by subst hadded; rfl))⟩
    rw [names', names]
    subst hadded
    simp [definedColumn]

end Belay.Sqlite.Model
