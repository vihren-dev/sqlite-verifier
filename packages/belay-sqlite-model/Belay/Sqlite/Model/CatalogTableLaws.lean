import Belay.Sqlite.Model.CatalogValidLaws

set_option doc.verso true

/-! {lit}`CatalogTable.supported` as a list of facts (ADR 0022, D3, slice 4). The check is a
conjunction of Boolean tests; the resolver facts prove and use the facts one by one. -/

namespace Belay.Sqlite.Model

/-- The facts that {name}`CatalogTable.supported` checks, for the given limits and table:
* the table has a column, and at most as many as the limits allow;
* no two columns have the same folded name, and no column has a name of the rowid;
* each position of the primary key is below the number of columns;
* each key of {name}`CatalogTable.uniqueKeys` is not empty and has only positions below the number of columns;
* a rowid alias at a position is the whole primary key, in a table that is not WITHOUT ROWID, and its
  column is not generated and has INTEGER affinity;
* each CHECK constraint reads only columns below the number of columns. -/
def CatalogTable.SupportedFacts (limits : Limits) (table : CatalogTable) : Prop :=
  table.columns ≠ [] ∧ table.columns.length ≤ limits.columns ∧
    (table.columns.map (·.name.folded)).Nodup ∧ (∀ column ∈ table.columns, rowidName column.name = false) ∧
    (∀ position ∈ table.primaryKey, position < table.columns.length) ∧
    (∀ key ∈ table.uniqueKeys, key ≠ [] ∧ ∀ position ∈ key, position < table.columns.length) ∧
    (∀ position, table.rowidAlias = some position → table.primaryKey = [position] ∧ table.withoutRowid = false ∧
      ∃ column, table.columns[position]? = some column ∧ column.generated = none ∧ column.affinity = .integer) ∧
    (∀ check ∈ table.allChecks, check.condition.readsBelow table.columns.length = true)

/-- For every table and limits, {name}`CatalogTable.supported` holds exactly when the table has the
facts of {name}`CatalogTable.SupportedFacts`. Proof sketch: unfold the Boolean tests into their
propositions; the names without duplicates are unique exactly when the folded names are
({name}`length_eraseDups_iff`). -/
theorem CatalogTable.supported_iff (limits : Limits) (table : CatalogTable) :
    table.supported limits = true ↔ table.SupportedFacts limits := by
  have names := (length_eraseDups_iff _ (table.columns.map (·.name.folded)) rfl).2
  simp only [List.length_map] at names
  have alias : table.aliasSupported = true ↔ ∀ position, table.rowidAlias = some position →
      table.primaryKey = [position] ∧ table.withoutRowid = false ∧
        ∃ column, table.columns[position]? = some column ∧ column.generated = none ∧
          column.affinity = .integer := by
    unfold CatalogTable.aliasSupported
    cases hrow : table.rowidAlias with
    | none => simp
    | some position =>
      simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true', Option.any_eq_true, Option.some.injEq,
        forall_eq', Option.isNone_iff_eq_none, beq_iff_eq]
      constructor
      · rintro ⟨⟨key, off⟩, column, found, none, integer⟩
        exact ⟨key, off, column, found, none, integer⟩
      · rintro ⟨key, off, column, found, none, integer⟩
        exact ⟨⟨key, off⟩, column, found, none, integer⟩
  unfold CatalogTable.supported CatalogTable.checksReadBelow supportedKey
  simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq, beq_iff_eq, List.isEmpty_iff,
    List.all_eq_true, Bool.or_eq_true, ne_eq, names, alias, CatalogTable.SupportedFacts]
  have primary : (table.primaryKey = [] ∨ table.primaryKey.isEmpty = false ∧
      ∀ position ∈ table.primaryKey, position < table.columns.length) ↔
      ∀ position ∈ table.primaryKey, position < table.columns.length := by
    cases table.primaryKey <;> simp
  have rowid : (table.columns.any fun column => rowidName column.name) = false ↔
      ∀ column ∈ table.columns, rowidName column.name = false := by simp
  rw [primary, rowid]
  simp only [and_assoc]
  simp

end Belay.Sqlite.Model
