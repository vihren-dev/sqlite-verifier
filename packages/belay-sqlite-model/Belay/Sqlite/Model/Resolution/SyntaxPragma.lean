import Belay.Sqlite.Model.Identifier

set_option doc.verso true

/-! The {lit}`PRAGMA` statements as written (ADR 0018, D4; ADR 0019, D2): the setting pragmas,
the pragmas that report facts of the schema, and the checks of the constraints. The frontend refuses every other pragma and a
schema name such as {lit}`main.`. -/

namespace Belay.Sqlite.Model.Syntax

/-- A pragma that sets or reads one setting of the connection. -/
inductive PragmaSetting where
  /-- {lit}`foreign_keys` (ADR 0018, D4). -/
  | foreignKeys
  /-- {lit}`recursive_triggers` (ADR 0019, D2). -/
  | recursiveTriggers
  deriving Repr, BEq, DecidableEq

/-- The name of the setting as SQLite gives it to the column of its query, for example
{lit}`foreign_keys`. -/
def PragmaSetting.sqlName : PragmaSetting → String
  | .foreignKeys => "foreign_keys"
  | .recursiveTriggers => "recursive_triggers"

/-- A {lit}`PRAGMA` statement of the model. The names of the tables are as written; the
frontend removes their quotes. -/
inductive Pragma where
  /-- {lit}`PRAGMA setting = value` or {lit}`PRAGMA setting(value)`, with the value as
  {lit}`sqlite3GetBoolean` reads it, or the query {lit}`PRAGMA setting` with
  {lean}`(none : Option Bool)`. -/
  | setting (setting : PragmaSetting) (value : Option Bool)
  /-- {lit}`PRAGMA table_info(table)`: one row for each column of the table that is not
  generated. -/
  | tableInfo (table : Identifier)
  /-- {lit}`PRAGMA foreign_key_list(table)`: one row for each column of each foreign key of the
  table. -/
  | foreignKeyList (table : Identifier)
  /-- {lit}`PRAGMA integrity_check` or, with {lit}`quick`, {lit}`PRAGMA quick_check`: the row
  {lit}`ok`, or one row for each failure of a constraint, at most {lit}`limit` rows, 100 for a
  {lit}`limit` of 0, for every table or the named one. -/
  | check (quick : Bool) (limit : Nat) (table : Option Identifier)
  /-- {lit}`PRAGMA foreign_key_check`, alone or with a table name: one row for each child row
  whose foreign key finds no parent row, for every table or the named one. -/
  | foreignKeyCheck (table : Option Identifier)
  deriving Repr, BEq, DecidableEq

/-- The name of the column of a check pragma, which is also the name of the pragma:
{lit}`quick_check` with {lit}`quick`, else {lit}`integrity_check`. -/
def checkName (quick : Bool) : String := if quick then "quick_check" else "integrity_check"

/-- Whether the pragma only reads: every form except a setting with a value. For example,
{lean}`(Pragma.setting .foreignKeys (some true)).readsOnly = false`. -/
def Pragma.readsOnly : Pragma → Bool
  | .setting _ value => value.isNone
  | .tableInfo _ | .foreignKeyList _ | .check .. | .foreignKeyCheck _ => true

end Belay.Sqlite.Model.Syntax
