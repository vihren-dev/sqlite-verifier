import Belay.Sqlite.Model.Resolution.Sources
import Belay.Sqlite.Model.Resolution.PragmaRows

set_option doc.verso true

/-! Resolution of the table-valued functions of {lit}`FROM`: the {lit}`json_each` sources
(ADR 0012, amendment 5, slice 6d; ADR 0013, D5), with the reference and its columns, and its
arguments, which read the sources before it; and the table-valued pragmas
{lit}`pragma_table_info` and {lit}`pragma_foreign_key_list` (ADR 0019, D2). The paths follow {lit}`Syntax.Statement.select` as in
{lit}`Sources.lean`; in a source, child 2 is the list of its arguments. -/

namespace Belay.Sqlite.Model

/-- The columns of {lit}`json_each` in SQLite's order, without declared types: the eight
that {lit}`*` shows, then the hidden {lit}`json` and {lit}`root`. -/
def eachColumns : List CatalogColumn :=
  [name! "key", name! "value", name! "type", name! "atom", name! "id", name! "parent",
    name! "fullkey", name! "path", name! "json", name! "root"].map fun name => { name, declaredType := none }

/-- The positions of the hidden columns {lit}`json` and {lit}`root` in
{name}`eachColumns`. -/
def eachHidden : List Nat := [8, 9]

/-- The largest number of arguments of {lit}`json_each` that SQLite accepts: the JSON and
the path ({lit}`too many arguments on json_each() - max 2`). -/
def maximumEachArguments : Nat := 2

/-- The source of one {lit}`json_each` reference at {lit}`path` with its arguments as
written, or the issue of a form that the model does not describe: another function or no
argument ({name}`RestrictionKind.tableFunction`), and more than
{name}`maximumEachArguments` arguments, which SQLite refuses. Its name is the alias, else
{lit}`json_each`, as SQLite names it in messages; two of its columns are hidden. -/
def eachReference (path : List Nat) (reference : Syntax.TableReference) (arguments : List Syntax.Expr) :
    Except ValueIssue ScopeSource :=
  if !reference.table.isKeyword (bytes! "json_each") || arguments.isEmpty then
    .error (.restriction path .tableFunction)
  else if arguments.length > maximumEachArguments then .error (.prepare .tooManyEachArguments)
  else .ok { name := reference.alias.getD (name! "json_each"), columns := eachColumns, hidden := eachHidden }

/-- Resolve the arguments of the {lit}`json_each` source at {lit}`index` of the scope, whose
reference is at {lit}`path`: each argument resolves over the whole scope, as SQLite does,
and then must read only the sources before it
({name}`RestrictionKind.laterSourceInArguments`). The first argument is the JSON and the
second, if any, the path. -/
def resolveEachArguments (dqs : Bool) (scope : Scope) (index : Nat) (path : List Nat)
    (arguments : List Syntax.Expr) : Except ValueIssue Resolved.Source := do
  let bound := scope.cellsBefore index
  let resolved ← resolveAll (fun position argument => do
    let (resolved, _) ← (resolveOperand dqs scope {} true argument).mapError (·.under (path ++ [2, position]))
    if resolved.readsBelow bound then .ok resolved
    else .error (.restriction (path ++ [2, position]) .laterSourceInArguments)) arguments
  match resolved with
  | json :: rest => .ok (.each json rest.head?)
  | [] => .error (.restriction path .tableFunction)

/-- The source of a table-valued pragma with the column names and rows of its pragma: each row
with the hidden cells {lit}`arg`, the argument, and {lit}`schema`, NULL, whose names are the
restriction {lit}`table-function` ({name}`ScopeSource.arguments`). The cells have no declared
type, so they have no affinity and the binary collation. -/
def pragmaSource (reference : Syntax.TableReference) (argument : List UInt8) (names : List String)
    (rows : List (List Value)) : Resolved.PragmaRows × ScopeSource :=
  (.fixed (names.length + 2) (rows.map (· ++ [.text argument, .null])),
    { name := reference.alias.getD reference.table,
      columns := (names ++ ["arg", "schema"]).map fun name => { name := .ofString name, declaredType := none },
      hidden := [names.length, names.length + 1], arguments := [names.length, names.length + 1] })

/-- The source of a table-valued pragma at {lit}`path` with its arguments as written:
{lit}`pragma_table_info('t')` with the rows of {name}`Catalog.tableInfoRows` and
{lit}`pragma_foreign_key_list('t')` with those of {name}`Catalog.foreignKeyListRows`, each with
one text literal as its argument ({name}`pragmaSource`). Every other pragma function, another
form of argument, and a name of a table of the catalog are the restriction
{name}`RestrictionKind.tableFunction`; a name of SQLite's own tables that the catalog does not
have is {name}`RestrictionKind.systemTable`. -/
def pragmaReference (catalog : Catalog) (path : List Nat) (reference : Syntax.TableReference)
    (arguments : List Syntax.Expr) : Except ValueIssue (Resolved.PragmaRows × ScopeSource) :=
  match arguments, catalog.findTable reference.table with
  | [.string argument], none =>
    if reference.table.isKeyword (bytes! "pragma_table_info") then
      match catalog.tableInfoRows ⟨argument⟩ with
      | some rows => .ok (pragmaSource reference argument tableInfoNames rows)
      | none => .error (.restriction path .systemTable)
    else if reference.table.isKeyword (bytes! "pragma_foreign_key_list") then
      .ok (pragmaSource reference argument foreignKeyListNames (catalog.foreignKeyListRows ⟨argument⟩))
    else .error (.restriction path .tableFunction)
  | _, _ => .error (.restriction path .tableFunction)

end Belay.Sqlite.Model
