import Belay.Sqlite.Model.Resolution.CatalogObjects
import Belay.Sqlite.Model.Resolution.ForeignKeyAction

set_option doc.verso true

/-! The rows of {lit}`PRAGMA table_info` and {lit}`PRAGMA foreign_key_list` (ADR 0019, D2), which
read only the catalog, as SQLite's {lit}`pragma.c` gives them. Resolution computes them, because
each statement resolves against the catalog of its own time. -/

namespace Belay.Sqlite.Model

/-- The text value of the UTF-8 bytes of a string. -/
def pragmaText (text : String) : Value := .text text.toUTF8.toList

/-- The names of the columns of {lit}`PRAGMA table_info`. -/
def tableInfoNames : List String := ["cid", "name", "type", "notnull", "dflt_value", "pk"]

/-- The names of the columns of {lit}`PRAGMA foreign_key_check`. -/
def foreignKeyCheckNames : List String := ["table", "rowid", "parent", "fkid"]

/-- The names of the columns of {lit}`PRAGMA foreign_key_list`. -/
def foreignKeyListNames : List String := ["id", "seq", "table", "from", "to", "on_update", "on_delete", "match"]

/-- The row of {lit}`PRAGMA table_info` for one column that is not generated, with its
{lit}`cid` and its position in the table:

* {lit}`type` is the declared type as SQLite keeps it ({name}`CatalogColumn.declaredType`),
  or the empty text without a type;
* {lit}`notnull` is 1 for a NOT NULL column, which includes a key column of a
  {lit}`WITHOUT ROWID` table;
* {lit}`dflt_value` is the text of the default as written ({name}`ColumnDefault.sourceText`),
  or NULL without a default;
* {lit}`pk` is the position of the column in the primary key, from 1, or 0. -/
def tableInfoRow (table : CatalogTable) (cid : Nat) (position : Nat) (column : CatalogColumn) : List Value :=
  [.integer cid, .text column.name.bytes, pragmaText (column.declaredType.getD ""),
    .integer (if column.notNull then 1 else 0),
    (column.defaultValue.map fun default => pragmaText default.sourceText).getD .null,
    .integer (Int.ofNat ((table.primaryKey.idxOf? position).map (· + 1) |>.getD 0))]

/-- The rows of {lit}`PRAGMA table_info` for a table: one row for each column that is not
generated, in column order, whose {lit}`cid` counts only these columns ({name}`tableInfoRow`). -/
def CatalogTable.infoRows (table : CatalogTable) : List (List Value) :=
  let stored := table.columns.zipIdx.filter fun (column, _) => column.generated.isNone
  stored.zipIdx.map fun ((column, position), cid) => tableInfoRow table cid position column

/-- The text value of a name, or NULL. -/
def nameValue : Option Identifier → Value
  | some name => .text name.bytes
  | none => .null

/-- The rows of {lit}`PRAGMA foreign_key_list` for one foreign key with its {lit}`id`: one row
for each of its columns, with the column's position in the key as {lit}`seq`; {lit}`to` is
the referenced column as written, or NULL without a column list. -/
def foreignKeyRows (table : CatalogTable) (id : Nat) (key : ForeignKey) : List (List Value) :=
  key.columns.zipIdx.map fun (position, seq) =>
    [.integer id, .integer seq, .text key.table.bytes, nameValue (table.columns[position]?.map (·.name)),
      nameValue key.referenced[seq]?, pragmaText key.onUpdate.sqlName, pragmaText key.onDelete.sqlName,
      pragmaText "NONE"]

/-- The rows of {lit}`PRAGMA foreign_key_list` for a table, by {lit}`id` and then {lit}`seq`
({name}`foreignKeyRows`). The ids count the keys newest first: SQLite keeps the keys of a table
in the reverse order of {name}`CatalogTable.allForeignKeys`. -/
def CatalogTable.foreignKeyListRows (table : CatalogTable) : List (List Value) :=
  table.allForeignKeys.reverse.zipIdx.flatMap fun (key, id) => foreignKeyRows table id key

/-- The rows of {lit}`PRAGMA table_info` of the table with the name ({name}`CatalogTable.infoRows`):
no rows when the catalog has no table with the name, as SQLite gives for a missing table, and
{lean}`(none : Option (List (List Value)))` for a name of SQLite's own tables that the catalog
does not have, such as {lit}`sqlite_schema`, whose columns the model does not describe. -/
def Catalog.tableInfoRows (catalog : Catalog) (table : Identifier) : Option (List (List Value)) :=
  match catalog.findTable table with
  | some (_, found) => some found.infoRows
  | none => if reservedName table then none else some []

/-- The rows of {lit}`PRAGMA foreign_key_list` of the table with the name
({name}`CatalogTable.foreignKeyListRows`), or no rows when the catalog has no table with the
name. SQLite's own tables have no foreign keys. -/
def Catalog.foreignKeyListRows (catalog : Catalog) (table : Identifier) : List (List Value) :=
  match catalog.findTable table with
  | some (_, found) => found.foreignKeyListRows
  | none => []

end Belay.Sqlite.Model
