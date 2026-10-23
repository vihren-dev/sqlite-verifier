import Belay.Sqlite.Model.ForeignKeyMatch
import Belay.Sqlite.Model.Database

set_option doc.verso true

/-! Whether a child row of a foreign key has its parent in a database (ADR 0018, D4; ADR 0022,
D1), as the writes check it: with a NULL in its key, or with a parent row that the key finds
({name}`Belay.Sqlite.Model.parentFound`). {lit}`PRAGMA foreign_key_check` and the fact
{lit}`Database.ForeignKeysHold` both use it. -/

namespace Belay.Sqlite.Model

/-- The rows of the table at a position, none for a position without a table. -/
def Database.rowsAt (database : Database) (position : Nat) : List Row :=
  (database.table position).map (·.rows) |>.getD []

/-- Whether a child row of a foreign key has what the key requires in the database: a NULL in
its key ({name}`ForeignKeyLink.hasNull`), or a row of the parent table that the key finds
({name}`parentFound`). A key whose parent table does not exist, or has no parent key
({name}`ParentLink.missing`, {name}`ParentLink.mismatch`), finds no parent row. -/
def ForeignKeyLink.satisfied (database : Database) (link : ForeignKeyLink) (row : Row) : Bool :=
  link.hasNull row.values || match link.parent with
    | .located parent key => match database.catalog.tableAt parent with
      | some shape => parentFound shape key link row.values (database.rowsAt parent) none
      | none => false
    | .mismatch _ | .missing => false

end Belay.Sqlite.Model
