import Belay.Sqlite.Model.Resolution.PragmaRows
import Belay.Sqlite.Model.TableInfoResolution

set_option doc.verso true

/-! The facts of the schema that {lit}`pragma_table_info('t')` states (ADR 0017, S4): the table lookup ignores ASCII case,
the rows of the pragma for a table of the catalog are the columns that are not generated, with their names, declared
types, NOT NULL flags and primary-key positions. -/

namespace Belay.Sqlite.Model

/-- For every catalog and two names that are the same name for SQLite (equal after ASCII lowercase,
{name}`Identifier.sameName`), the catalog finds the same table for both. The formula says nothing of names that differ
after ASCII lowercase, such as {lit}`É` and {lit}`é`. Proof sketch: the lookup tests {name}`Identifier.sameName` of
each object with the name, and the test with a name equals the test with the other name when the two names have equal
folds. -/
theorem Catalog.findTable_sameName (catalog : Catalog) (left right : Identifier) (same : left.sameName right = true) :
    catalog.findTable left = catalog.findTable right := by
  have folds : left.folded = right.folded := by simpa [Identifier.sameName] using same
  have test : ∀ object : CatalogObject, object.name.sameName left = object.name.sameName right := by
    intro object
    simp [Identifier.sameName, folds]
  simp [Catalog.findTable, Catalog.find, test]

/-- For every catalog and name for which the catalog finds a table, the rows of {lit}`pragma_table_info` for the name are
the rows of the table that the pragma gives ({name}`CatalogTable.infoRows`). Proof sketch: the definition of
{name}`Catalog.tableInfoRows` for a name that the catalog finds. -/
theorem Catalog.tableInfoRows_of_findTable (catalog : Catalog) (name : Identifier) (position : Nat) (table : CatalogTable)
    (found : catalog.findTable name = some (position, table)) : catalog.tableInfoRows name = some table.infoRows := by
  simp [Catalog.tableInfoRows, found]

/-- Every pair of the indexed list has a first part that is an item of the list. Proof sketch: the first parts of the
indexed list are the list ({name}`List.zipIdx_map_fst`). -/
theorem List.mem_of_mem_zipIdx_fst {α : Type} {list : List α} {start : Nat} {pair : α × Nat} (member : pair ∈ list.zipIdx start) :
    pair.1 ∈ list := by
  have := List.mem_map_of_mem (f := Prod.fst) member
  rwa [List.zipIdx_map_fst] at this

/-- Every item of a list is the first part of some pair of the indexed list. Proof sketch: the first parts of the indexed
list are the list ({name}`List.zipIdx_map_fst`). -/
theorem List.exists_mem_zipIdx_of_mem {α : Type} {list : List α} {start : Nat} {item : α} (member : item ∈ list) :
    ∃ index, (item, index) ∈ list.zipIdx start := by
  have : item ∈ (list.zipIdx start).map Prod.fst := by rwa [List.zipIdx_map_fst]
  obtain ⟨⟨found, index⟩, inside, rfl⟩ := List.mem_map.mp this
  exact ⟨index, inside⟩

/-- For every table, argument and predicate of four values, some row of {lit}`pragma_table_info` passes the predicate
on its name, declared type, NOT NULL flag and primary-key position exactly when a column of the table that is not
generated passes it on those metadata values. The column position is its index in the full column list. The declared
type is empty text when absent; the flag is 1 when the column is marked NOT NULL and 0 otherwise. The primary-key
position is the first position of the column in the key, counted from 1, or 0 outside the key.
For example, a predicate can require a column named {lit}`cents` with declared type {lit}`INTEGER`. Use
{lean}`fun (_ _ _ _ : Value) => True` to ask only whether a row exists. The argument and NULL are the two hidden cells of each row.
Proof sketch: remove the two maps of {name}`CatalogTable.infoRows`, retain the full column position through the filter,
and read the four cells of {name}`tableInfoRow`. The extra index after the filter changes only the unused CID cell. -/
theorem CatalogTable.exists_pragmaRow_metadata (table : CatalogTable) (argument : List UInt8)
    (test : Value → Value → Value → Value → Prop) :
    (∃ row ∈ table.infoRows.map (· ++ [Value.text argument, Value.null]),
      test (row[1]?.getD .null) (row[2]?.getD .null) (row[3]?.getD .null) (row[5]?.getD .null)) ↔
      ∃ entry ∈ table.columns.zipIdx, entry.1.generated.isNone = true ∧
        test (.text entry.1.name.bytes) (pragmaText (entry.1.declaredType.getD ""))
          (.integer (if entry.1.notNull then 1 else 0))
          (.integer (Int.ofNat ((table.primaryKey.idxOf? entry.2).map (· + 1) |>.getD 0))) := by
  unfold CatalogTable.infoRows
  simp only [List.mem_map]
  constructor
  · rintro ⟨row, ⟨info, ⟨⟨⟨column, position⟩, cid⟩, member, rfl⟩, rfl⟩, passes⟩
    have stored := List.mem_of_mem_zipIdx_fst member
    simp only at stored
    obtain ⟨inColumns, generated⟩ := List.mem_filter.mp stored
    exact ⟨(column, position), inColumns, by simpa using generated, by simpa [tableInfoRow] using passes⟩
  · rintro ⟨⟨column, position⟩, indexed, generated, passes⟩
    obtain ⟨cid, stored⟩ := List.exists_mem_zipIdx_of_mem (start := 0)
      (List.mem_filter (p := fun pair : CatalogColumn × Nat => pair.fst.generated.isNone).mpr ⟨indexed, generated⟩)
    exact ⟨_, ⟨_, ⟨_, stored, rfl⟩, rfl⟩, by simpa [tableInfoRow] using passes⟩

/-- For every table, argument and test {lit}`Q` of a value, some row of the pragma {lit}`pragma_table_info` for the table
(a row of {name}`CatalogTable.infoRows` with the argument and NULL as its two hidden cells) passes the test with its name
column (cell 1) exactly when the table has a column that is not generated whose name, as text, passes the test. The test
sees the bytes of the name, so a test of equality with a text is a comparison of bytes and the case of the letters
matters. Proof sketch: specialize {name}`CatalogTable.exists_pragmaRow_metadata` to the name cell and remove the unused
column index with {name}`List.zipIdx_map_fst`. -/
theorem CatalogTable.exists_pragmaRow_name (table : CatalogTable) (argument : List UInt8) (test : Value → Prop) :
    (∃ row ∈ table.infoRows.map (· ++ [Value.text argument, Value.null]), test (row[1]?.getD Value.null)) ↔
      ∃ column ∈ table.columns, column.generated.isNone = true ∧ test (.text column.name.bytes) := by
  rw [table.exists_pragmaRow_metadata argument (fun name _ _ _ => test name)]
  constructor
  · rintro ⟨⟨column, position⟩, indexed, generated, named⟩
    exact ⟨column, List.mem_of_mem_zipIdx_fst indexed, generated, named⟩
  · rintro ⟨column, inColumns, generated, named⟩
    obtain ⟨position, indexed⟩ := List.exists_mem_zipIdx_of_mem (start := 0) inColumns
    exact ⟨(column, position), indexed, generated, named⟩

/-- For every value and bytes, the value compares equal to the text of the bytes under {lit}`BINARY` exactly when the value is that
text. The formula includes a NULL and the numbers: they rank below a text, so they never compare equal to it. Proof
sketch: a value of another storage class has another rank; a text has the same rank and number, so only the bytes are
compared. -/
theorem Collation.binary_compare_text (value : Value) (bytes : List UInt8) :
    Collation.binary.compare value (.text bytes) = .eq ↔ value = .text bytes := by
  cases value <;> simp [Collation.compare, Collation.key, Value.compare, compareLex, compareOn, Value.rank, Value.scaled,
    Value.bytes, Ordering.then]
  rename_i bits
  by_cases ranked : (realScaled bits).isSome = true <;> simp [ranked]

/-- For every reference, argument and rows, the unqualified name {lit}`name` resolves in the scope of
{lit}`pragma_table_info` ({name}`tableInfoScope`) to the cell 1 of the pragma, read alone. Proof sketch: the scope has
one source with the eight cells of {name}`pragmaSource`, and only cell 1 has the name; the computation does not read the
name of the source. -/
theorem tableInfoScope_resolveName_name (reference : Syntax.TableReference) (argument : List UInt8)
    (rows : List (List Value)) :
    (tableInfoScope reference argument rows).resolveName (name! "name") = .found 1 [1] := by
  have position : columnPosition (tableInfoNames.map (fun name =>
      ({ name := Identifier.ofString name, declaredType := none } : CatalogColumn)) ++
      [{ name := Identifier.ofString "arg", declaredType := none }, { name := Identifier.ofString "schema", declaredType := none }])
      (name! "name") = some 1 := by
    decide +kernel
  simp [tableInfoScope, pragmaSource, Scope.place, Scope.resolveName, Scope.depths, Scope.resolveAt, Scope.resolveStep,
    position]

/-- For every reference, argument, rows, quote kind, shapes and misuse flag, the name {lit}`name` resolves in the scope of
{lit}`pragma_table_info` ({name}`tableInfoScope`) to cell 1 of the pragma, with the affinity {lit}`BLOB` of a column without
a declared type, which converts nothing. Proof sketch: the name resolves to cell 1 alone ({name}`tableInfoScope_resolveName_name`), and the cell is neither an
argument cell nor a trigger cell. -/
theorem resolveOperand_tableInfo_name (dqs : Bool) (reference : Syntax.TableReference) (argument : List UInt8)
    (rows : List (List Value)) (quote : Syntax.QuoteKind) (shapes : SubqueryShapes) (misuse : Bool) :
    resolveOperand dqs (tableInfoScope reference argument rows) shapes misuse (.identifier (name! "name") quote) =
      .ok (.column 1, some .blob) := by
  simp only [resolveOperand, tableInfoScope_resolveName_name]
  simp [Scope.nameRead, Scope.nameOperand, Scope.affinityAt, tableInfoScope, pragmaSource, Scope.place, Scope.argumentCell,
    Scope.triggerCell, Scope.columns, tableInfoNames, CatalogColumn.affinity, affinityOf]

/-- For every reference, argument and rows, the collation of cell 1 of the pragma {lit}`pragma_table_info`, which holds the
name, is {lit}`BINARY` ({name}`tableInfoScope`): the cells of the pragma have no declared collation, so the comparison of the
name with a text compares bytes. Proof sketch: the scope has the eight cells of {name}`pragmaSource`, which have the
default collation. -/
theorem tableInfoScope_collation_name (reference : Syntax.TableReference) (argument : List UInt8)
    (rows : List (List Value)) :
    (tableInfoScope reference argument rows).columns[1]?.map (·.collation) = some Collation.binary := by
  simp [tableInfoScope, pragmaSource, Scope.place, tableInfoNames, Scope.columns]

end Belay.Sqlite.Model
