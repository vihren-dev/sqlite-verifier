import Belay.Sqlite.Model.ResolveCreateTableCatalog
import Belay.Sqlite.Model.ResolveIndexBelow
import Belay.Sqlite.Model.ResolveFinishShaped

set_option doc.verso true

/-! CREATE INDEX gives a valid catalog (ADR 0022, D3, slice 4): when the resolver of a script
appends an index to a valid catalog, the catalog stays valid. The keys and the filter read below
the width of the indexed table ({lit}`indexKeys_below`, {lit}`indexFilter_below`), and the table
stays at its position in the longer catalog. -/

namespace Belay.Sqlite.Model

open Resolved

/-- For every index and width: if
* the index has at least one key;
* the term of every key is below the width ({name}`KeyTerm.Below`);
* the filter of the index, when it has one, reads no column from the width on;

then {name}`CatalogIndex.supported` holds for the index and the width. Proof sketch: the definition
is a conjunction of exactly these facts; the column positions and the expression terms are the
two cases of {name}`KeyTerm.Below`. -/
theorem CatalogIndex.supported_of_below {index : CatalogIndex} {width : Nat}
    (nonempty : index.keys ≠ []) (below : ∀ key ∈ index.keys, key.term.Below width)
    (filter : ∀ resolved, index.filter = some resolved → resolved.any (Expr.isColumnFrom width) = false) :
    index.supported width = true := by
  unfold CatalogIndex.supported
  simp only [Bool.and_eq_true, List.all_eq_true, List.mem_filterMap, Bool.not_eq_true',
    List.isEmpty_eq_false_iff, decide_eq_true_eq]
  refine ⟨⟨⟨nonempty, ?_⟩, ?_⟩, ?_⟩
  · rintro position ⟨key, member, found⟩
    have := below key member
    cases hterm : key.term <;> simp [hterm] at found
    subst found
    simpa [hterm, KeyTerm.Below] using this
  · intro key member
    have := below key member
    cases hterm : key.term <;> simp [hterm, KeyTerm.Below] at this ⊢
    simp [Expr.readsBelow, this]
  · cases present : index.filter with
    | none => rfl
    | some resolved => simp [Expr.readsBelow, filter resolved present]

/-- For every catalog, name, position and table: if {name}`Catalog.findTable` finds the table of the
name at the position, then {name}`Catalog.tableAt` gives the table at the position. Proof sketch:
{name}`Catalog.findTable_some` gives the object at the position, and its entry is the table. -/
theorem Catalog.tableAt_of_findTable {catalog : Catalog} {name : Identifier} {position : Nat}
    {table : CatalogTable} (found : catalog.findTable name = some (position, table)) :
    catalog.tableAt position = some table := by
  obtain ⟨object, atPosition, entry, _⟩ := Catalog.findTable_some catalog name position table found
  unfold Catalog.tableAt
  rw [atPosition]
  rcases object with ⟨objectName, objectEntry⟩
  simp only at entry
  subst entry
  rfl

/-- For every scope, columns, terms and keys: if the terms resolve to the keys ({name}`indexKeys`),
there is at least one key. Proof sketch: the resolver refuses an empty list of terms, and resolving
the terms one by one gives one key for each term ({name}`mapM_ok_map_eq`). -/
theorem indexKeys_ne_nil {dqs : Bool} {scope : Scope} {columns : List CatalogColumn}
    {terms : List Syntax.OrderTerm} {keys : List IndexKey}
    (ok : indexKeys dqs scope columns terms = .ok keys) : keys ≠ [] := by
  unfold indexKeys at ok
  split at ok
  · cases ok
  rename_i notEmpty
  have lengths := congrArg List.length
    (mapM_ok_map_eq _ (fun _ => ()) (fun _ => ()) (fun _ _ _ => rfl) ok)
  simp only [List.length_map, List.length_zipIdx] at lengths
  rintro rfl
  have : terms = [] := List.length_eq_zero_iff.mp lengths.symm
  simp [this] at notEmpty

/-- For every valid catalog, table position, table, name, keys, uniqueness flag and filter: if
* {name}`Catalog.findTable` finds the table at the position;
* the name is not reserved;
* the catalog does not find the name;
* the keys are not empty;
* the term of every key is below the number of columns of the table;
* the filter, when there is one, reads no column from that number on;

then the catalog with the index appended ({name}`Catalog.createIndex`) is valid. Proof sketch: the
index is supported under the longer catalog, because the table keeps its position
({name}`Catalog.tableAt_append_of_some`) and {name}`CatalogIndex.supported_of_below` applies;
{name}`Catalog.Valid.append` ends the proof. -/
theorem Catalog.Valid.createIndex {limits : Limits} {catalog : Catalog} {position : Nat}
    {table : CatalogTable} {name tableName : Identifier} {keys : List IndexKey} {unique : Bool}
    {filter : Option Resolved.Expr} (valid : catalog.Valid limits)
    (found : catalog.findTable tableName = some (position, table)) (notReserved : reservedName name = false)
    (fresh : catalog.find name = none) (nonempty : keys ≠ [])
    (below : ∀ key ∈ keys, key.term.Below table.columns.length)
    (filtered : ∀ resolved, filter = some resolved → resolved.any (Expr.isColumnFrom table.columns.length) = false) :
    (catalog.createIndex name { table := position, keys, unique, filter }).Valid limits := by
  refine valid.append _ (fun _ => fresh) ?_
  have present := Catalog.tableAt_append_of_some [{ name, entry := .index { table := position, keys, unique, filter } }]
    (Catalog.tableAt_of_findTable found)
  simp only [CatalogObject.supported, notReserved, present, Bool.not_false, Bool.true_and, Option.any_some]
  exact CatalogIndex.supported_of_below nonempty below filtered

/-- For every context, valid catalog and successful resolution of CREATE INDEX, the catalog after the
resolution is valid. Proof sketch: split every branch of the resolver. A prepare error returns the
catalog. The branch that appends an index is {name}`Catalog.Valid.createIndex`, with the keys and the
filter below the width of the table ({name}`indexKeys_below`, {name}`indexFilter_below`) and the
keys not empty ({name}`indexKeys_ne_nil`). -/
theorem resolveCreateIndex_valid (context : ResolveContext) (catalog after : Catalog) (name : Identifier)
    (unique : Bool) (tableName : Identifier) (terms : List Syntax.OrderTerm) (filter : Option Syntax.Expr)
    (statement : Resolved.Statement) (valid : catalog.Valid context.profile.limits)
    (ok : resolveCreateIndex context catalog name unique tableName terms filter = .ok (statement, after)) :
    after.Valid context.profile.limits := by
  unfold resolveCreateIndex at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact valid)
    | (exact absurd (Catalog.find_not_trigger _ _ _ _ (by assumption)) (by simp [CatalogObject.isTrigger,
        CatalogEntry.isTrigger]))
    | (cases ok; done)
    | (cases ok
       exact Catalog.Valid.createIndex valid (by assumption) (by simp_all) (by assumption)
         (indexKeys_ne_nil (by assumption)) (indexKeys_below (Scope.single_bounded _ _ _) (by assumption))
         (fun resolved present => indexFilter_below (Scope.single_bounded _ _ _) (by rw [← present]; assumption)))

end Belay.Sqlite.Model
