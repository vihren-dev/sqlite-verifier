import Belay.Sqlite.Model.UniqueLookupCompare
import Belay.Sqlite.Model.KeysUniqueLookup
import Belay.Sqlite.Model.CountMatchingLaws

set_option doc.verso true

/-! The bound of a unique lookup (ADR 0017, S4, outcome 6): in a table whose keys are unique, the comparison
{lit}`c = v` of a column {lit}`c` with a value {lit}`v` that has no affinity is true for at most one row, when the
comparison uses the collation of a unique key of the column. -/

namespace Belay.Sqlite.Model

/-- For every storage affinity, the NULL cell is in the stored form of the affinity
({name}`LiteralData.storedForm`). Proof sketch: case analysis on the affinity; the store leaves NULL. -/
theorem storedForm_null (affinity : Affinity) : LiteralData.storedForm affinity .null = true := by
  cases affinity <;> rfl

/-- For every row that is stored for the columns ({name}`Row.Stored`), column position and column at it: the cell of the
row at the position, or NULL when the row has no cell there, is in the stored form of the column's affinity
({name}`LiteralData.storedForm`). Proof sketch: a present cell is stored by the hypothesis; a missing cell is NULL
({name}`storedForm_null`). -/
theorem Row.Stored.storedForm_getD {columns : List CatalogColumn} {row : Row} (stored : row.Stored columns)
    {index : Nat} {column : CatalogColumn} (columnAt : columns[index]? = some column) :
    LiteralData.storedForm column.affinity (row.values.getD index .null) = true := by
  cases cellAt : row.values[index]? with
  | none => simp [List.getD_eq_getElem?_getD, cellAt, storedForm_null]
  | some cell =>
    simp only [List.getD_eq_getElem?_getD, cellAt, Option.getD_some, LiteralData.storedForm, beq_iff_eq]
    exact stored index column cell columnAt cellAt

namespace Resolved

/-- For every affinity of the comparison, collation, two cells and a value: if, when the comparison
has an affinity, each cell is in the stored form of that affinity ({name}`LiteralData.storedForm`; with no
affinity nothing is required of the cells), and the comparison {lit}`cell = value` is true for both cells
({name}`comparisonOperands`, {name}`truthy`), then the two cells conflict as key cells
({name}`LiteralData.keyCellsEqual`) under the collation. Proof sketch: each cell is not NULL and equal to the probe of
the value ({name}`cell_eq_probe`); equality under a collation is symmetric and transitive. -/
theorem keyCellsEqual_of_accepted {affinity : Option Affinity} {collation : Collation} {first second value : Value}
    (firstStored : ∀ column, affinity = some column → LiteralData.storedForm column first = true)
    (secondStored : ∀ column, affinity = some column → LiteralData.storedForm column second = true)
    (firstAccepted : truthy (Comparison.eq.apply (comparisonOperands affinity first value).1
      (comparisonOperands affinity first value).2 collation) = true)
    (secondAccepted : truthy (Comparison.eq.apply (comparisonOperands affinity second value).1
      (comparisonOperands affinity second value).2 collation) = true) :
    LiteralData.keyCellsEqual first second collation = true := by
  obtain ⟨firstPresent, firstEqual⟩ := cell_eq_probe firstStored firstAccepted
  obtain ⟨secondPresent, secondEqual⟩ := cell_eq_probe secondStored secondAccepted
  simp only [LiteralData.keyCellsEqual, Bool.and_eq_true, bne_iff_ne, beq_iff_eq]
  exact ⟨⟨firstPresent, secondPresent⟩, Std.TransCmp.eq_trans firstEqual (Std.OrientedCmp.eq_symm secondEqual)⟩

/-- For every parameters and number of rows: the condition {lit}`n <= 1`, with the subquery value {lit}`n`
({name}`Resolved.SubqueryRun.count`) in the context of the parameters, with no affinity, under the binary collation,
against the integer literal 1, is true ({name}`truthy`) exactly when the number
is at most one. Proof sketch: the comparison of two integers under any collation is the order of the integers
({name}`Collation.compare_integer`). -/
theorem truthy_count_le_one (parameters : List Value) (n : Nat) :
    truthy ((Expr.compare .le none (.subquery 0) (.literal (.integer 1)) .binary).eval
      ((EvalContext.bound parameters).withRuns [SubqueryRun.count n]) []) = decide (n ≤ 1) := by
  simp [Expr.eval_compare, Expr.eval_subquery, Expr.eval_literal, EvalContext.withRuns_subqueries, comparisonOperands,
    SubqueryRun.count, Value.isNull, Comparison.holds, Collation.compare_integer, truth, truthy, Comparison.apply]
  rcases Int.lt_trichotomy (n : Int) 1 with less | equal | greater
  · simp [Int.compare_eq_lt.2 less, show n ≤ 1 by omega]
  · simp [equal, show n ≤ 1 by omega]
  · simp [Int.compare_eq_gt.2 greater, show ¬ n ≤ 1 by omega]

end Resolved

/-- The bound of a unique lookup, for every table, key and column: if the table satisfies {name}`Table.KeysUnique` for
the keys and {name}`Table.RowsStored`, the key is one of the keys with no filter and with one term, the column at
position {lit}`index`, under a collation, and a comparison {lit}`cell = value` has
* the affinity of the column ({lean}`some column.affinity`), so the value has no affinity of its own;
* the collation of the key term;
* a right operand that evaluates to the given cell in the given context for every list of cell values
  ({name}`Resolved.Expr.eval`), so it depends on no row;

then at most one stored row makes the comparison true ({name}`Resolved.truthy`), so
{name}`Resolved.countMatching` of the comparison is at most one. The lemma holds only for the collation of the key term: a column with {lit}`COLLATE NOCASE` and a unique index with
{lit}`COLLATE BINARY` can store {lit}`'a'` and {lit}`'A'`, and both match {lit}`c = 'a'`. The lemma does not cover a value with an affinity of its own. Proof sketch: two rows that make the comparison
true conflict on the key ({name}`Resolved.keyCellsEqual_of_accepted`), which the table forbids for rows in the list
({name}`filter_length_le_one_of_pairwise`). -/
theorem Table.KeysUnique.countMatching_le_one {keys : List UniqueKey} {table : Table}
    (unique : table.KeysUnique keys) (stored : table.RowsStored) {key : UniqueKey} (member : key ∈ keys)
    {index : Nat} {descending : Bool} {collation : Collation} {column : CatalogColumn}
    (columnAt : table.shape.columns[index]? = some column) (noFilter : key.filter = none)
    (oneTerm : key.terms = [{ term := .column index, descending, collation }])
    (context : Resolved.EvalContext) (value : Resolved.Expr) (cell : Value)
    (constant : ∀ row : List Value, value.eval context row = cell) :
    Resolved.countMatching context
      (some (.compare .eq (some column.affinity) (.column index) value collation)) table ≤ 1 := by
  rw [Resolved.countMatching_eq]
  refine filter_length_le_one_of_pairwise ((unique key member).imp_of_mem fun {first second} firstMember secondMember distinct both => ?_)
  simp only [Option.all_some] at both
  simp only [Resolved.Expr.eval_compare, Resolved.Expr.eval_column, constant] at both
  have cellAccepted := Resolved.keyCellsEqual_of_accepted (affinity := some column.affinity) (collation := collation)
    (fun _ same => by obtain rfl := Option.some.inj same; exact (stored first firstMember).storedForm_getD columnAt)
    (fun _ same => by obtain rfl := Option.some.inj same; exact (stored second secondMember).storedForm_getD columnAt)
    both.1 both.2
  have present : ∀ row : Row, row.values.getD index .null ≠ .null →
      row.values[index]? = some (row.values.getD index .null) := fun row nonNull => by
    cases cellAt : row.values[index]? <;> simp_all [List.getD_eq_getElem?_getD]
  have nonNull := cellAccepted
  simp only [LiteralData.keyCellsEqual, Bool.and_eq_true, bne_iff_ne] at nonNull
  have firstCell := present first nonNull.1.1
  have secondCell := present second nonNull.1.2
  have conflict : LiteralData.keyEqual key first second = true := by
    unfold LiteralData.keyEqual
    simp only [noFilter, oneTerm, LiteralData.keyApplies, List.all_cons, List.all_nil, LiteralData.termValue,
      LiteralData.read, firstCell, secondCell, cellAccepted, Bool.and_true]
  simp [conflict] at distinct

/-- For every catalog, position, table and list of column positions: if the list is a {lit}`UNIQUE` constraint of the
table ({name}`CatalogTable.uniqueKeys`), the key of these columns under their collations ({name}`UniqueKey.ofColumns`)
is a unique key of the table ({name}`Catalog.uniqueKeys`). Proof sketch: the keys of the table list the keys of its
constraints first. -/
theorem Catalog.ofColumns_mem_uniqueKeys_of_unique (catalog : Catalog) (position : Nat) (table : CatalogTable)
    {columns : List Nat} (declared : columns ∈ table.uniqueKeys) :
    UniqueKey.ofColumns table.columns columns ∈ catalog.uniqueKeys position table :=
  List.mem_append_left _ (List.mem_map_of_mem (List.mem_append_right _ declared))

/-- For every catalog, position and table with a {lit}`PRIMARY KEY`: the key of the columns of the primary key under their
collations ({name}`UniqueKey.ofColumns`) is a unique key of the table ({name}`Catalog.uniqueKeys`). Proof sketch: the
keys of the table list its primary key first. -/
theorem Catalog.ofColumns_mem_uniqueKeys_of_primaryKey (catalog : Catalog) (position : Nat) (table : CatalogTable)
    (declared : table.primaryKey.isEmpty = false) :
    UniqueKey.ofColumns table.columns table.primaryKey ∈ catalog.uniqueKeys position table := by
  refine List.mem_append_left _ (List.mem_map_of_mem (List.mem_append_left _ ?_))
  simp [declared]

end Belay.Sqlite.Model
