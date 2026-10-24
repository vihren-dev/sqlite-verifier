import Belay

set_option doc.verso true

/-! A fixture of {lit}`tests/surface_schema_claims_test.py` for the metadata law in {lit}`Model/TableInfoLaws.lean`.
The same concrete schema checks both sides of the law with kernel proofs, then checks the SQL observations. Generated
columns separate the full column positions from the pragma CIDs; a reversed composite key checks the key positions. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- A schema with declared and absent types, both NOT NULL flags, and two kinds of generated column. The primary key
lists the text column first, although the integer column comes first in the table. -/
def metadataDb : Database := db! r"
  CREATE TABLE metadata (
    left_id INTEGER NOT NULL,
    virtual_value INTEGER AS (left_id + 1) VIRTUAL,
    right_id TEXT NOT NULL,
    stored_value TEXT AS (right_id) STORED,
    loose,
    PRIMARY KEY (right_id, left_id)
  );"

/-- The catalog table whose column metadata the pragma exposes. -/
def metadataTable : CatalogTable :=
  (metadataDb.raw.catalog.findTable (name! "metadata")).get (by decide +kernel) |>.2

/-- For every schema and argument, the metadata law can test a named INTEGER column that is NOT NULL and second in
the primary key. Its right side keeps the full column position and excludes generated columns. Proof sketch:
specialize {name}`CatalogTable.exists_pragmaRow_metadata` to these four metadata tests. -/
theorem integer_second_key_metadata (table : CatalogTable) (argument : List UInt8) :
    (∃ row ∈ table.infoRows.map (· ++ [Value.text argument, Value.null]),
      row[1]?.getD .null = .text (bytes! "left_id") ∧ row[2]?.getD .null = pragmaText "INTEGER" ∧
      row[3]?.getD .null = .integer 1 ∧ row[5]?.getD .null = .integer 2) ↔
    ∃ entry ∈ table.columns.zipIdx, entry.1.generated.isNone = true ∧
      .text entry.1.name.bytes = Value.text (bytes! "left_id") ∧
      pragmaText (entry.1.declaredType.getD "") = pragmaText "INTEGER" ∧
      Value.integer (if entry.1.notNull then 1 else 0) = .integer 1 ∧
      Value.integer (Int.ofNat ((table.primaryKey.idxOf? entry.2).map (· + 1) |>.getD 0)) = .integer 2 :=
  table.exists_pragmaRow_metadata argument
    (fun name type flag key => name = .text (bytes! "left_id") ∧ type = pragmaText "INTEGER" ∧
      flag = .integer 1 ∧ key = .integer 2)

-- Both sides of the equivalence hold for the integer column of the concrete schema.
example : ∃ row ∈ metadataTable.infoRows.map (· ++ [Value.text (bytes! "metadata"), Value.null]),
    row[1]?.getD .null = .text (bytes! "left_id") ∧ row[2]?.getD .null = pragmaText "INTEGER" ∧
    row[3]?.getD .null = .integer 1 ∧ row[5]?.getD .null = .integer 2 :=
  (integer_second_key_metadata metadataTable (bytes! "metadata")).2 (by decide +kernel)

-- Both sides fail if the claimed type differs; the law preserves the declared type exactly.
example : ¬ ∃ row ∈ metadataTable.infoRows.map (· ++ [Value.text (bytes! "metadata"), Value.null]),
    row[1]?.getD .null = .text (bytes! "left_id") ∧ row[2]?.getD .null = pragmaText "TEXT" ∧
    row[3]?.getD .null = .integer 1 ∧ row[5]?.getD .null = .integer 2 := by
  rw [metadataTable.exists_pragmaRow_metadata (bytes! "metadata")
    (fun name type flag key => name = .text (bytes! "left_id") ∧ type = pragmaText "TEXT" ∧
      flag = .integer 1 ∧ key = .integer 2)]
  decide +kernel

-- The full column position 2 is first in the primary key, despite a generated column before it.
example : ∃ row ∈ metadataTable.infoRows.map (· ++ [Value.text (bytes! "metadata"), Value.null]),
    row[1]?.getD .null = .text (bytes! "right_id") ∧ row[2]?.getD .null = pragmaText "TEXT" ∧
    row[3]?.getD .null = .integer 1 ∧ row[5]?.getD .null = .integer 1 := by
  apply (metadataTable.exists_pragmaRow_metadata (bytes! "metadata")
    (fun name type flag key => name = .text (bytes! "right_id") ∧ type = pragmaText "TEXT" ∧
      flag = .integer 1 ∧ key = .integer 1)).2
  decide +kernel

-- The nullable column without a type or key position receives empty text, 0 and 0.
example : ∃ row ∈ metadataTable.infoRows.map (· ++ [Value.text (bytes! "metadata"), Value.null]),
    row[1]?.getD .null = .text (bytes! "loose") ∧ row[2]?.getD .null = pragmaText "" ∧
    row[3]?.getD .null = .integer 0 ∧ row[5]?.getD .null = .integer 0 := by
  apply (metadataTable.exists_pragmaRow_metadata (bytes! "metadata")
    (fun name type flag key => name = .text (bytes! "loose") ∧ type = pragmaText "" ∧
      flag = .integer 0 ∧ key = .integer 0)).2
  decide +kernel

-- Both generated columns are in the catalog, and neither has a row in table_info.
example : ∃ column ∈ metadataTable.columns,
    column.name.bytes = bytes! "virtual_value" ∧ column.generated.isSome = true := by decide +kernel
example : ∃ column ∈ metadataTable.columns,
    column.name.bytes = bytes! "stored_value" ∧ column.generated.isSome = true := by decide +kernel
example : ¬ ∃ row ∈ metadataTable.infoRows.map (· ++ [Value.text (bytes! "metadata"), Value.null]),
    row[1]?.getD .null = .text (bytes! "virtual_value") := by
  rw [metadataTable.exists_pragmaRow_name (bytes! "metadata") (fun value => value = .text (bytes! "virtual_value"))]
  decide +kernel
example : ¬ ∃ row ∈ metadataTable.infoRows.map (· ++ [Value.text (bytes! "metadata"), Value.null]),
    row[1]?.getD .null = .text (bytes! "stored_value") := by
  rw [metadataTable.exists_pragmaRow_name (bytes! "metadata") (fun value => value = .text (bytes! "stored_value"))]
  decide +kernel

-- SQL reads the same metadata and gives an empty result for a wrong type or either generated column.
example : Holds (sql r"SELECT 1 FROM pragma_table_info('metadata')
    WHERE name = 'left_id' AND type = 'INTEGER' AND [notnull] = 1 AND pk = 2") metadataDb := by decide +kernel
example : Holds (sql r"SELECT 1 FROM pragma_table_info('metadata')
    WHERE name = 'right_id' AND type = 'TEXT' AND [notnull] = 1 AND pk = 1") metadataDb := by decide +kernel
example : Holds (sql r"SELECT 1 FROM pragma_table_info('metadata')
    WHERE name = 'loose' AND type = '' AND [notnull] = 0 AND pk = 0") metadataDb := by decide +kernel
example : Empty (sql r"SELECT 1 FROM pragma_table_info('metadata')
    WHERE name = 'left_id' AND type = 'TEXT'") metadataDb := by decide +kernel
example : Empty (sql r"SELECT 1 FROM pragma_table_info('metadata')
    WHERE name = 'virtual_value' OR name = 'stored_value'") metadataDb := by decide +kernel
