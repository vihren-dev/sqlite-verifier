import Belay.Sqlite.Model.ForeignKeySatisfied
import Belay.Sqlite.Model.TableBlocks
import Belay.Sqlite.Model.QueryEval

set_option doc.verso true

/-! The rows of {lit}`PRAGMA foreign_key_check` (ADR 0019, D2), as SQLite 3.51.0 gives them
({lit}`pragma.c`, {lit}`PragTyp_FOREIGN_KEY_CHECK`): one row for each child row and foreign key
that the row does not satisfy ({lit}`ForeignKeyLink.satisfied`), also when foreign keys are
off. A {lit}`foreign key mismatch` fails at prepare, so resolution reports it. -/

namespace Belay.Sqlite.Model

/-- The row of {lit}`PRAGMA foreign_key_check` for a row of the table {lit}`name` that does not
satisfy the foreign key {lit}`link` with the id {lit}`id`: the table name as declared, the
rowid of the row or NULL for a {lit}`WITHOUT ROWID` table, the parent table as the key writes
it, and the id. -/
def foreignKeyCheckRow (name : Identifier) (shape : CatalogTable) (row : Row) (link : ForeignKeyLink) (id : Nat) :
    List Value :=
  [.text name.bytes, if shape.withoutRowid then .null else .integer row.rowid, .text link.key.table.bytes, .integer id]

/-- The rows of {lit}`PRAGMA foreign_key_check` for the table at the catalog position: for each
row in scan order ({name}`Belay.Sqlite.Model.Table.scanRows`), for each foreign key of the
table in the order of its id ({name}`childLinks`, newest first), the row
{name}`foreignKeyCheckRow` when the row does not satisfy the key
({name}`ForeignKeyLink.satisfied`). A row with a NULL in the key satisfies it, and a key whose
parent table is missing finds no parent row. -/
def Database.keyCheckRows (database : Database) (position : Nat) (table : Table) : List (List Value) :=
  let name := (database.catalog[position]?.map (·.name)).getD default
  let links := (childLinks database.catalog.foreignKeyLinks position).zipIdx
  table.scanRows.flatMap fun row => links.filterMap fun (link, id) =>
    if link.satisfied database row then none else some (foreignKeyCheckRow name table.shape row link id)

/-- The rows of {lit}`PRAGMA foreign_key_check` over the database for the tables of
{name}`Database.checkPositions`, with the rows of each table that gives rows
({name}`Database.blocks` of {name}`Database.keyCheckRows`):

* no rows when no table gives rows;
* the rows of the one table that gives rows;
* {lean}`(none : Option (List (List Value)))` when two or more tables give rows, because SQLite
  checks the tables in the order of its schema hash table, which the model does not
  describe. -/
def Database.foreignKeyCheckRows (database : Database) (table : Option Nat) : Option (List (List Value)) :=
  match database.blocks (database.checkPositions table) database.keyCheckRows with
  | [] => some []
  | [rows] => some rows
  | _ :: _ :: _ => none

end Belay.Sqlite.Model
