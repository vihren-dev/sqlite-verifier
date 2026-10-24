import Belay.Sqlite.Model.ResolveStatementFacts
import Belay.Sqlite.Model.Resolution.ResolveStateSpec

set_option doc.verso true

/-! The catalog that a resolved statement leaves (ADR 0022, D3, slice 4): for a valid resolution state in
execution mode, the catalog that {lit}`Resolved.Statement.applyCatalog` gives for a resolved statement is
valid, and the index of a resolved CREATE INDEX is supported for the width of its table. These are the
facts that the statement theorems of "catalog supported" and of "keys unique" ask for CREATE INDEX. -/

namespace Belay.Sqlite.Model

/-- For every statement that is transaction control or a setting ({name}`Resolved.Statement.isControl`) and
every catalog, {name}`Resolved.Statement.applyCatalog` gives the catalog. Proof sketch: a case for each
control statement; the others contradict the premise. -/
theorem Resolved.Statement.applyCatalog_of_control {statement : Resolved.Statement}
    (control : statement.isControl = true) (catalog : Catalog) : statement.applyCatalog catalog = catalog := by
  cases statement <;> first | rfl | cases control

/-- For every context in execution mode, state, statement and resolution: if the state is valid under the
limits of the profile of the context ({name}`ResolveState.Valid`), the catalog that
{name}`Resolved.Statement.applyCatalog` gives for the resolved statement on the catalog of the state is
valid under the limits. Proof sketch: for transaction control and a setting the catalog does not change;
for every other statement the next state has this catalog ({name}`resolveStatement_after`,
{name}`ResolveState.after_of_isControl`) and is valid ({name}`resolveStatement_valid`). -/
theorem resolveStatement_applyCatalog_valid (context : ResolveContext) (state next : ResolveState)
    (statement : Syntax.Statement) (resolved : Resolved.Statement) (execution : context.mode = .execution)
    (valid : state.Valid context.profile.limits)
    (ok : resolveStatement context state statement = .ok (resolved, next)) :
    (resolved.applyCatalog state.catalog).Valid context.profile.limits := by
  cases control : resolved.isControl
  · have after := resolveStatement_after context state next statement resolved ok
    rw [state.after_of_isControl control] at after
    have valid' := resolveStatement_valid context state next statement resolved execution valid ok
    rw [after] at valid'
    exact valid'.1
  · rw [Resolved.Statement.applyCatalog_of_control control]
    exact valid.1

/-- For every catalog, name, index and position of a catalog with the index appended, and every table at
the position: the position holds the same table before. Proof sketch: a position below the length reads the
same object; a position at the length holds the index, which is no table. -/
theorem Catalog.tableAt_createIndex {catalog : Catalog} {name : Identifier} {index : CatalogIndex} {position : Nat}
    {table : CatalogTable} (present : (catalog.createIndex name index).tableAt position = some table) :
    catalog.tableAt position = some table := by
  unfold Catalog.createIndex Catalog.tableAt at present
  unfold Catalog.tableAt
  by_cases below : position < catalog.length
  · rwa [List.getElem?_append_left below] at present
  · rw [List.getElem?_append_right (Nat.not_lt.mp below)] at present
    cases same : position - catalog.length with
    | zero => simp [same] at present
    | succ _ => simp [same] at present

/-- For every catalog, name and index: if the catalog with the index appended ({name}`Catalog.createIndex`)
is valid under limits, the index is supported for the width of its table ({name}`CatalogIndex.supported`),
and the table is in the catalog. Proof sketch: the validity gives the support of the appended object, whose
table is a table of the longer catalog; the position of the table is below the length
({name}`Catalog.tableAt_createIndex`). -/
theorem Catalog.createIndex_supported {limits : Limits} {catalog : Catalog} {name : Identifier} {index : CatalogIndex}
    (valid : (catalog.createIndex name index).Valid limits) :
    ((catalog.tableAt index.table).any fun table => index.supported table.columns.length) = true := by
  have supported := valid.object (object := { name, entry := .index index })
    (List.mem_append_right _ (List.mem_singleton_self _))
  simp only [CatalogObject.supported, Bool.and_eq_true] at supported
  obtain ⟨_, table⟩ := supported
  cases found : (catalog.createIndex name index).tableAt index.table with
  | none => simp [found] at table
  | some shape =>
    rw [Catalog.tableAt_createIndex found]
    simpa [found] using table

end Belay.Sqlite.Model
