import Belay.Sqlite.SqlTerm
import Belay.Sqlite.SqlDiagnostics
import Belay.Sqlite.EvalDatabase

set_option doc.verso true

/-! {lit}`sql! db r"..."`: the script of {lit}`sql r"..."`, which also resolves its statements
against the catalog of the database {lit}`db` while the file elaborates, as {lit}`db.run` does
when it starts. Each prepare error, such as {lit}`no such column: nmae`, and the first model
restriction are elaboration errors at the name or node in the SQL text. -/

namespace Belay.Sqlite

open Lean Elab Term

/-- {lit}`sql! db "SQL"`: the script of the statements of the SQL text, as {lit}`sql "SQL"`
gives it, after a check of the statements against the database {lit}`db`, which must have a
value while the file elaborates. The term does not use {lit}`db`, so
{lit}`sql! db r"..."` and {lit}`sql r"..."` are equal by {lit}`rfl`. Use {lit}`sql` for a script
that runs on a database that is a variable. -/
syntax:max (name := sqlBangTerm) "sql! " term:max str : term

/-- Elaborate {lit}`sql! db "SQL"`: translate the text, evaluate {lit}`db`
({name}`evaluateDatabase`), log each error of {name}`scriptDiagnostics` at its range of the text
({name}`textRange`), and give the term of {lit}`sql "SQL"` ({name}`scriptTerm`). When {lit}`db` has an error, which
Lean already shows, it gives the script without the check. -/
@[term_elab sqlBangTerm]
def elabSqlBang : TermElab := fun term _ => do
  let literal := term[2]
  let some text := literal.isStrLit? | throwUnsupportedSyntax
  let items ← literalStatements literal
  if let some database ← evaluateDatabase term[1] then
    for diagnostic in scriptDiagnostics database.raw.connection.resolveState text.toUTF8 (items.toList.map (·.statement)) do
      logErrorAt (textRange literal text diagnostic.start diagnostic.stop) diagnostic.message
  scriptTerm literal text items

end Belay.Sqlite
