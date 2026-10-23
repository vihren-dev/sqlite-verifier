import Belay.Sqlite.Run
import Belay.Sqlite.SqlTerm

set_option doc.verso true

/-! The command {lit}`#sql db r"..."`: it runs the script on the database and shows the output of
each statement in the editor, rows as a table with the names of the columns. For example,
{lit}`#sql shop r"SELECT * FROM invoices"` shows the table of the invoices. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- The outputs of a run as {lit}`#sql` shows them: the text of each output, one after the other,
with an empty line between two outputs. -/
structure Tables where
  /-- The text that {lit}`#sql` shows. -/
  text : String

instance : Repr Tables where
  reprPrec tables _ := tables.text

/-- The outputs of the script on the database ({name}`Database.Raw.run`), each with the names of
its result columns ({name}`scriptResultNames`), as {lit}`#sql` shows them ({name}`Output.table`). -/
def Database.tables (db : Database) (script : Script) : Tables :=
  let names := scriptResultNames runContext none db.raw.connection script.statements
  { text := "\n\n".intercalate (((db.raw.run script).outputs.zip names).map fun (output, columns) => output.table columns) }

/-- {lit}`#sql db r"..."` shows the output of each statement of the script on the database
({name}`Database.tables`). The text is a script as {lit}`sql r"..."` reads it, so its errors
are at their positions in the text. -/
syntax (name := sqlCommand) "#sql " term:max str : command

macro_rules
  | `(#sql $db $text) => `(#eval Belay.Sqlite.Database.tables $db (sql $text))

end Belay.Sqlite
