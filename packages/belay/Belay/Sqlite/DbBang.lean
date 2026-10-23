import Belay.Sqlite.SqlTerm
import Belay.Sqlite.DbDiagnostics

set_option doc.verso true

/-! {lit}`db! r"..."`: the database that the SQL text builds on the empty database while the file
elaborates. Each statement that fails, and the statement that ends the run, is an elaboration
error at its position in the text. The term holds the database as a literal and the decision of
{lit}`Database.Valid` for it, which the kernel checks. -/

namespace Belay.Sqlite

open Lean Elab Term Meta

/-- {lit}`db! "SQL"`: the database that the statements of the SQL text build on the empty
database, as {lit}`(Database.Raw.run {} (sql "SQL")).connection.state.database` gives it. For
example, {lit}`db! r"CREATE TABLE t(a); INSERT INTO t VALUES (1)"` is a database with the table
{lit}`t` and one row. Use {lit}`Database.empty` for a database without tables. -/
syntax (name := dbBangTerm) "db! " str : term

/-- The term of the database: {name}`Database.mk` of the literal of the model database and of
the proof {lit}`of_decide_eq_true (Eq.refl true)`, so the kernel decides {name}`Database.Valid`
for the literal when it checks the term. -/
def databaseExpr (raw : Database.Raw) : Expr :=
  let literal := toExpr raw
  let pinned := Lean.mkConst ``Profile.pinned
  let valid := mkApp2 (Lean.mkConst ``Belay.Sqlite.Model.Database.Valid) pinned literal
  let decision := mkApp2 (Lean.mkConst ``Belay.Sqlite.Model.Database.decidableValid) pinned literal
  let decided := mkApp2 (Lean.mkConst ``Eq.refl [Level.one]) (Lean.mkConst ``Bool) (Lean.mkConst ``Bool.true)
  mkApp2 (Lean.mkConst ``Database.mk) literal (mkApp3 (Lean.mkConst ``of_decide_eq_true) valid decision decided)

/-- The message of a database that the text builds and that is not valid, with the atom of
{name}`Database.Valid` that fails ({name}`Belay.Sqlite.Model.ValidityAtom.name`). -/
def invalidDatabaseMessage (atom : Belay.Sqlite.Model.ValidityAtom) : String :=
  s!"the database that db! builds is not valid: {atom.name} does not hold. The model's " ++
    "statements keep a database valid, so this is a defect of the model; report the SQL text " ++
    "to the maintainers of the model"

/-- The term of the database that a text builds with no error: {name}`databaseExpr` for a
valid database, or the error {name}`invalidDatabaseMessage` with the first atom that fails
({name}`Belay.Sqlite.Model.Database.failingAtom?`). The kernel decides
{name}`Belay.Sqlite.Model.Database.Valid` again when it checks the term. -/
def databaseTerm (raw : Database.Raw) : Except String Expr :=
  match raw.failingAtom? Profile.pinned with
  | some atom => .error (invalidDatabaseMessage atom)
  | none => .ok (databaseExpr raw)

/-- The error of a parameter in the text of {lit}`db!`: the database literal has no arguments, so
the parameter has no value. -/
def parameterDiagnostic (parameter : Translation.Parameter) : Diagnostic :=
  { start := parameter.start, stop := parameter.stop,
    message := s!"the parameter {parameter.text} has no value, because db! has no arguments; " ++
      "write the value in the SQL text in place of the parameter" }

/-- Elaborate {lit}`db! "SQL"`: translate the text, give an error at each parameter
({name}`parameterDiagnostic`), or else run the text on the empty database and log each error
of {name}`runDiagnostics` at its range of the text ({name}`textRange`). After an error, the term
is a {lit}`sorry` that Lean shows no second error for. Otherwise the term is
{name}`databaseTerm` of the database, and its error is an error at the literal. -/
@[term_elab dbBangTerm]
def elabDbBang : TermElab := fun term _ => do
  let literal := term[1]
  let some text := literal.isStrLit? | throwUnsupportedSyntax
  let items ← literalStatements literal
  let parameters := items.toList.flatMap (·.parameters)
  let (diagnostics, connection) := if parameters.isEmpty then runDiagnostics text.toUTF8 (items.toList.map (·.statement))
    else (parameters.map parameterDiagnostic, Database.empty.raw.connection)
  for diagnostic in diagnostics do
    logErrorAt (textRange literal text diagnostic.start diagnostic.stop) diagnostic.message
  if !diagnostics.isEmpty then
    return ← mkLabeledSorry (mkConst ``Database) (synthetic := true) (unique := false)
  match databaseTerm connection.state.database with
  | .error message => throwErrorAt literal message
  | .ok database => return database

end Belay.Sqlite
