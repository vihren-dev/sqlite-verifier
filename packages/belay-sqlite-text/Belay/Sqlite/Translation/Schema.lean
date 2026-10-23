import Belay.Sqlite.Translation.Constraints

set_option doc.verso true

/-! DROP TABLE, DROP INDEX, DROP TRIGGER, CREATE INDEX and the pragmas of the model. The port of
{lit}`belay/sqlite/syntax_drops.py`, {lit}`syntax_indexes.py` and {lit}`syntax_pragmas.py`. -/

namespace Belay.Sqlite.Translation

open Belay.Sqlite.Model

/-- {lit}`DROP TABLE|INDEX|TRIGGER [IF EXISTS] name`, with the name as written. -/
def drop (tree : SqlTree) (command : ParseNode) : TranslateM (Located Syntax.Statement) := do
  let kind := ((tree.children command)[1]?.map (·.symbol)).getD ""
  let parts ← require tree command ["DROP", kind, "ifexists", "fullname"]
  let full := parts[3]!
  unless tree.symbols full == ["nm"] do unsupported full "A schema name is not modeled; remove it"
  let make : Identifier → Bool → Syntax.Statement := match kind with
    | "TABLE" => .dropTable | "INDEX" => .dropIndex | _ => .dropTrigger
  let existsNode := parts[2]!
  let dropped ← identifierName tree (tree.children full)[0]!
  return composite (make dropped.value (!existsNode.children.isEmpty)) command.start command.stop
    #[dropped.span, spanOf existsNode]

/-- {lit}`CREATE [UNIQUE] INDEX name ON table(terms) [WHERE filter]`. -/
def createIndex (tree : SqlTree) (command : ParseNode) : TranslateM (Located Syntax.Statement) := do
  let parts ← require tree command ["createkw", "uniqueflag", "INDEX", "ifnotexists", "nm", "dbnm", "ON", "nm",
    "LP", "sortlist", "RP", "where_opt"]
  absent parts[3]! "IF NOT EXISTS"
  absent parts[5]! "A schema name"
  let whereParts := tree.children parts[11]!
  let filter ← if whereParts.isEmpty then pure (missing parts[11]!.start parts[11]!.stop)
    else Located.present <$> queryExpression tree whereParts[1]!
  let indexName ← identifierName tree parts[4]!
  let table ← identifierName tree parts[7]!
  let terms := sequence (← orderTerms queryMappers tree parts[9]!) parts[9]!.start parts[9]!.stop
  return composite (.createIndex indexName.value (!parts[1]!.children.isEmpty) table.value terms.value filter.value)
    command.start command.stop #[indexName.span, spanOf parts[1]!, table.span, terms.span, filter.span]

/-- The boolean words of {lit}`sqlite3GetBoolean`, in the order that the Python translation
tries them. -/
def booleanWords : List (String × Bool) :=
  [("on", true), ("yes", true), ("true", true), ("off", false), ("no", false), ("false", false)]

/-- The refusal of a {lit}`PRAGMA foreign_keys` value that the model does not read. -/
def pragmaValues : String :=
  "Only on, off, yes, no, true, false, 0 and 1 are modeled as the value of PRAGMA foreign_keys and recursive_triggers"

/-- The boolean of an {lit}`nmnum` value, or its refusal. -/
def settingValue (tree : SqlTree) (node : ParseNode) : TranslateM Bool := do
  let parts := tree.children node
  match tree.symbols node with
  | ["plus_num"] =>
    if tree.symbols parts[0]! == ["INTEGER"] then
      match tree.text parts[0]! with
      | "0" => return false
      | "1" => return true
      | _ => pure ()
  | ["ON"] | ["nm"] =>
    let word := if parts[0]!.symbol == "nm" then dequote (tree.text parts[0]!) else "on"
    if let some (_, value) := booleanWords.find? fun (known, _) => asciiEqual word known then return value
  | _ => pure ()
  unsupported node pragmaValues

/-- The refusal of a pragma that the model does not describe. -/
def modeledPragmas : String :=
  "Only PRAGMA foreign_keys, recursive_triggers, table_info, foreign_key_list, foreign_key_check, integrity_check and quick_check are modeled, without a schema name"

/-- The value node of a pragma: the {lit}`nmnum` or {lit}`minus_num` after {lit}`=` or in
parentheses, none without a value, or the refusal of another form. -/
def pragmaValue (tree : SqlTree) (command : ParseNode) : TranslateM (Option ParseNode) := do
  let parts := tree.children command
  match tree.symbols command with
  | ["PRAGMA", "nm", "dbnm"] => return none
  | ["PRAGMA", "nm", "dbnm", "EQ", _] | ["PRAGMA", "nm", "dbnm", "LP", _, "RP"] => return some parts[4]!
  | _ => unsupported command modeledPragmas

/-- The table name of the value node of a pragma: a name or a string, without its quotes. -/
def pragmaTableName (tree : SqlTree) (node : ParseNode) : TranslateM Identifier := do
  if tree.symbols node == ["nm"] then return (← identifierName tree (tree.children node)[0]!).value
  unsupported node "Only a table name is modeled as the value of this pragma"

/-- The table name of {lit}`PRAGMA table_info` or {lit}`PRAGMA foreign_key_list`: a name or a
string after {lit}`=` or in parentheses ({name}`pragmaTableName`). -/
def pragmaTable (tree : SqlTree) (command : ParseNode) (value : Option ParseNode) : TranslateM Identifier := do
  match value with
  | some node => pragmaTableName tree node
  | none => unsupported command "Write the table name in parentheses, for example PRAGMA table_info(t)"

/-- The refusal of a value of a check pragma that the model does not read. -/
def checkValues : String :=
  "Only a decimal row limit up to 2147483647 or a table name is modeled as the value of PRAGMA integrity_check and quick_check"

/-- The decimal integer of the text, if it has only digits and is at most 2147483647, the
values that SQLite's {lit}`sqlite3GetInt32` reads. -/
def checkLimitOf (text : String) : Option Nat :=
  if !text.isEmpty && text.all Char.isDigit then
    let value := text.foldl (fun value digit => value * 10 + (digit.toNat - '0'.toNat)) 0
    if value ≤ 2147483647 then some value else none
  else none

/-- The row limit and the table name of the value of a check pragma, as SQLite reads it: an
integer without quotes, also after {lit}`+` or {lit}`-`, whose sign SQLite ignores, is the limit;
a name or a string is the table name. Every other value is refused ({name}`checkValues`). -/
def checkValue (tree : SqlTree) (node : ParseNode) : TranslateM (Nat × Option Identifier) := do
  let parts := tree.children node
  let integer : Option ParseNode := match tree.symbols node with
    | ["plus_num"] => match tree.symbols parts[0]! with
      | ["INTEGER"] => some parts[0]!
      | ["PLUS", "INTEGER"] => (tree.children parts[0]!)[1]?
      | _ => none
    | ["MINUS", "INTEGER"] => parts[1]?
    | _ => none
  match integer with
  | some digits => match checkLimitOf (tree.text digits) with
    | some limit => return (limit, none)
    | none => unsupported node checkValues
  | none =>
    if tree.symbols node == ["nm"] then return (0, some (← identifierName tree parts[0]!).value)
    unsupported node checkValues

/-- A pragma of the model ({name}`Belay.Sqlite.Model.Syntax.Pragma`), with its name in any ASCII
case: {lit}`PRAGMA foreign_keys [= value]` and {lit}`PRAGMA foreign_keys(value)`, whose value is
none for the query form, and the same forms of {lit}`PRAGMA recursive_triggers`; {lit}`PRAGMA table_info(t)` and {lit}`PRAGMA foreign_key_list(t)`, also
with {lit}`= t`; {lit}`PRAGMA foreign_key_check`, alone or with a table name; and
{lit}`PRAGMA integrity_check` and {lit}`PRAGMA quick_check`, alone or with a value
({name}`checkValue`). -/
def pragma (tree : SqlTree) (command : ParseNode) : TranslateM (Located Syntax.Statement) := do
  let parts := tree.children command
  unless parts.size ≥ 3 && parts[2]!.children.isEmpty do unsupported command modeledPragmas
  let name := dequote (tree.text parts[1]!)
  let value ← pragmaValue tree command
  let form ← if asciiEqual name "foreign_keys" then
      (Syntax.Pragma.setting .foreignKeys ·) <$> value.mapM (settingValue tree)
    else if asciiEqual name "recursive_triggers" then
      (Syntax.Pragma.setting .recursiveTriggers ·) <$> value.mapM (settingValue tree)
    else if asciiEqual name "table_info" then Syntax.Pragma.tableInfo <$> pragmaTable tree command value
    else if asciiEqual name "foreign_key_list" then Syntax.Pragma.foreignKeyList <$> pragmaTable tree command value
    else if asciiEqual name "foreign_key_check" then Syntax.Pragma.foreignKeyCheck <$> value.mapM (pragmaTableName tree)
    else if asciiEqual name "integrity_check" || asciiEqual name "quick_check" then do
      let (limit, table) ← match value with
        | some node => checkValue tree node
        | none => pure (0, none)
      pure (Syntax.Pragma.check (asciiEqual name "quick_check") limit table)
    else unsupported command modeledPragmas
  return composite (.pragma form) command.start command.stop #[spanOf command]

end Belay.Sqlite.Translation
