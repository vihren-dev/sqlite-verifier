import Belay.Sqlite.Model.ResolveTableConstraintsShaped
import Belay.Sqlite.Model.ResolveTermsBelow
import Belay.Sqlite.Model.Resolution.GeneratedColumns

set_option doc.verso true

/-! The last steps of CREATE TABLE keep the invariant of the table (ADR 0022, D3, slice 4): the
resolution of the CHECK constraints ({lit}`resolveTableChecks`) and of the generated columns
({lit}`resolveGeneratedColumns`) change the CHECK constraints and the generated expressions, but not
the layouts of the columns, the keys, the alias or the rowid kind. -/

namespace Belay.Sqlite.Model

/-- For every function that can fail, two functions on the results and the elements, and list: if
the function keeps the value of the first function in the value of the second, and mapping it over the
list gives the results, the first function over the results gives the second function over the list.
Proof sketch: induction over the list. -/
theorem mapM_ok_map_eq {ε α β γ : Type} (f : α → Except ε β) (project : β → γ) (expected : α → γ)
    (keeps : ∀ item result, f item = .ok result → project result = expected item) :
    ∀ {items : List α} {results : List β}, items.mapM f = .ok results → results.map project = items.map expected
  | [], results, ok => by
    simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at ok; subst ok; rfl
  | item :: rest, results, ok => by
    simp only [List.mapM_cons, exceptBind_eq_ok] at ok
    obtain ⟨first, hfirst, later, hlater, same⟩ := ok
    simp only [pure, Except.pure, Except.ok.injEq] at same; subst same
    simp only [List.map_cons, keeps _ _ hfirst, mapM_ok_map_eq f project expected keeps hlater]

/-- For every columns and definitions that are equally many, and every function on the columns, the values of the function on the first columns of the numbered pairs of columns and definitions are the values of the function on the columns. Proof sketch: dropping the numbers and the definitions of the pairs leaves the columns ({name}`List.map_fst_zip`).  -/
theorem map_zipped_columns {α : Type} (columns : List CatalogColumn) (definitions : List Syntax.ColumnDefinition)
    (equal : columns.length = definitions.length) (value : CatalogColumn → α) :
    ((columns.zip definitions).zipIdx.map fun item => value item.1.1) = columns.map value := by
  have first : (columns.zip definitions).zipIdx.map (fun item => value item.1.1) =
      ((columns.zip definitions).zipIdx.map Prod.fst).map (fun pair => value pair.1) := by
    rw [List.map_map]; rfl
  have second : (columns.zip definitions).map (fun pair => value pair.1) =
      ((columns.zip definitions).map Prod.fst).map value := by
    rw [List.map_map]; rfl
  rw [first, List.zipIdx_map_fst, second, List.map_fst_zip (by omega)]

/-- For every table with as many columns as definitions: if {name}`resolveTableChecks` gives a table,
the table has the layouts of the columns, the primary key, the UNIQUE keys, the rowid alias and the rowid
kind of the table. Proof sketch: the columns are the checked columns, which have the layouts of the columns
({name}`mapM_ok_map_eq`); no column is left to append, because there are as many columns as
definitions. -/
theorem resolveTableChecks_keeps {dqs : Bool} {scope : Scope} {table result : CatalogTable}
    {definitions : List Syntax.ColumnDefinition} {constraints : List Syntax.TableConstraint}
    (equal : table.columns.length = definitions.length)
    (ok : resolveTableChecks dqs scope table definitions constraints = .ok result) :
    result.columns.map CatalogColumn.layout = table.columns.map CatalogColumn.layout ∧
      result.primaryKey = table.primaryKey ∧ result.uniqueKeys = table.uniqueKeys ∧
      result.rowidAlias = table.rowidAlias ∧ result.withoutRowid = table.withoutRowid := by
  simp only [resolveTableChecks, exceptBind_eq_ok] at ok
  obtain ⟨checked, hc, _, _, same⟩ := ok
  cases same
  have layouts := mapM_ok_map_eq _ CatalogColumn.layout (fun item => item.1.1.layout) (fun item result hf => by
    simp only [exceptFmap_eq_ok, exceptMapError_eq_ok] at hf
    obtain ⟨_, _, rfl⟩ := hf
    rfl) hc
  rw [List.drop_of_length_le (by omega)] at *
  exact ⟨by simpa [map_zipped_columns _ _ equal] using layouts, rfl, rfl, rfl, rfl⟩

/-- For every table with as many columns as definitions: if {name}`resolveGeneratedColumns` gives a
table, the table has the layouts and the CHECK constraints of the columns, the CHECK constraints, the
keys, the alias and the rowid kind of the table. Proof sketch: a column changes only the expression of
a generated column, which keeps the generated flag and the checks ({name}`mapM_ok_map_eq`); no column is
left to append. -/
theorem resolveGeneratedColumns_keeps {dqs : Bool} {scope : Scope} {table result : CatalogTable}
    {definitions : List Syntax.ColumnDefinition}
    (equal : table.columns.length = definitions.length)
    (ok : resolveGeneratedColumns dqs scope table definitions = .ok result) :
    result.columns.map CatalogColumn.layout = table.columns.map CatalogColumn.layout ∧
      result.columns.map (·.checks) = table.columns.map (·.checks) ∧ result.checks = table.checks ∧
      result.primaryKey = table.primaryKey ∧ result.uniqueKeys = table.uniqueKeys ∧
      result.rowidAlias = table.rowidAlias ∧ result.withoutRowid = table.withoutRowid := by
  simp only [resolveGeneratedColumns, exceptBind_eq_ok] at ok
  obtain ⟨columns, hc, rest⟩ := ok
  have pairs := mapM_ok_map_eq _ (fun column => (column.layout, column.checks))
    (fun item => (item.1.1.layout, item.1.1.checks)) (fun item result hf => by
      cases hg : item.1.1.generated with
      | none => cases hd : item.1.2.generatedExpression <;> (simp only [hg, hd] at hf; cases hf; rfl)
      | some how =>
        cases hd : item.1.2.generatedExpression with
        | none => simp only [hg, hd] at hf; cases hf; rfl
        | some pair =>
          obtain ⟨item', expression⟩ := pair
          simp only [hg, hd, exceptFmap_eq_ok, exceptMapError_eq_ok] at hf
          obtain ⟨_, _, rfl⟩ := hf
          simp [CatalogColumn.layout, hg]) hc
  rw [map_zipped_columns _ _ equal (fun column => (column.layout, column.checks))] at pairs
  have columnsEq : columns ++ table.columns.drop definitions.length = columns := by
    rw [List.drop_of_length_le (by omega)]; simp
  split at rest
  · cases rest
    simp only [columnsEq, and_true]
    refine ⟨?_, ?_⟩
    · simpa [List.map_map, Function.comp_def] using congrArg (List.map Prod.fst) pairs
    · simpa [List.map_map, Function.comp_def] using congrArg (List.map Prod.snd) pairs
  · cases rest

end Belay.Sqlite.Model
