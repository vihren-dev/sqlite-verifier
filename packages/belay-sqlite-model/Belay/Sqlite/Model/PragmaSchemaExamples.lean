import Belay.Sqlite.Model.ScriptRun
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the pragmas that report facts of the schema (ADR 0019, D2), each checked by the
kernel: {lit}`PRAGMA table_info` and {lit}`PRAGMA foreign_key_list`, and their table-valued forms
{lit}`pragma_table_info('t')` and {lit}`pragma_foreign_key_list('t')` in {lit}`FROM`. The rows are
SQLite's (3.51.0, checked natively with the {lit}`sqlite3` shell); a query without
{lit}`ORDER BY` gives them in normal form. -/

namespace Belay.Sqlite.Model.PragmaSchemaExamples

open Belay.Sqlite.Model Syntax Resolution.Examples

/-- The outputs of a run of the statements from the empty database, with the default profile. -/
def outputs (script : List Syntax.Statement) : List Output :=
  (runScriptFrom { profile := defaults, mode := .execution } none 0 { state := { database := {} } }
    (script.map (·, []))).outputs

/-- A column with a declared type and constraints. -/
def typed (text : String) (declaredType : Option String) (constraints : List ColumnConstraint := []) :
    ColumnDefinition :=
  { name := .ofString text, declaredType, constraints }

/-- A text value. -/
def textValue (text : String) : Value := .text text.toUTF8.toList

/-- A name as written, without quotes. -/
def name (text : String) : Expr := .identifier (.ofString text) .none

/-- {lit}`CREATE TABLE t(a INTEGER PRIMARY KEY, b "x""y" NOT NULL DEFAULT 'q', g AS (a + 1), c int
DEFAULT (5), d DEFAULT null)`: a rowid alias, a quoted type, a generated column, a standard
type in lower case, a default in parentheses and {lit}`DEFAULT null`. -/
def createT : Syntax.Statement :=
  .createTable (name! "t") [typed "a" (some "INTEGER") [.primaryKey false],
    typed "b" (some "x\"y") [.notNull, .default (.string "q".toUTF8.toList) "'q'"],
    typed "g" none [.generated (.arithmetic .add (name "a") (.numeric "1")) none],
    typed "c" (some "int") [.default (.numeric "5") "5"], typed "d" none [.default .null "null"]] []

-- One row for each column that is not generated; cid counts only them. The type is as
-- written, and a standard type is in capitals; the rowid alias is pk 1.
example : outputs [createT, .pragma (.tableInfo (name! "T"))] = [.done 0, .rows [
    [.integer 0, textValue "a", textValue "INTEGER", .integer 0, .null, .integer 1],
    [.integer 1, textValue "b", textValue "x\"y", .integer 1, textValue "'q'", .integer 0],
    [.integer 2, textValue "c", textValue "INT", .integer 0, textValue "5", .integer 0],
    [.integer 3, textValue "d", textValue "", .integer 0, textValue "null", .integer 0]]] := by
  decide +kernel

/-- {lit}`CREATE TABLE w(a, b, PRIMARY KEY(b, a)) WITHOUT ROWID`. -/
def createW : Syntax.Statement :=
  .createTable (name! "w") [typed "a" none, typed "b" none] [.primaryKey [name! "b", name! "a"]] { withoutRowid := true }

-- The key columns of a WITHOUT ROWID table are NOT NULL; pk is the position in the key.
example : outputs [createW, .pragma (.tableInfo (name! "w"))] = [.done 0, .rows [
    [.integer 0, textValue "a", textValue "", .integer 1, .null, .integer 2],
    [.integer 1, textValue "b", textValue "", .integer 1, .null, .integer 1]]] := by
  decide +kernel

-- A missing table gives no rows; a table of SQLite's own that the catalog does not have ends the run.
example : outputs [.pragma (.tableInfo (name! "missing")), .pragma (.foreignKeyList (name! "missing"))] =
    [.rows [], .rows []] := by decide +kernel
example : (outputs [.pragma (.tableInfo (name! "sqlite_schema"))]).map Output.endsRun = [true] := by decide +kernel

/-- {lit}`CREATE TABLE c(x REFERENCES p, y, z, FOREIGN KEY (y, z) REFERENCES q(a, b) ON DELETE
CASCADE)`. -/
def createC : Syntax.Statement :=
  .createTable (name! "c") [typed "x" none [.references (name! "p") [] .noAction .noAction], typed "y" none,
    typed "z" none] [.foreignKey [name! "y", name! "z"] (name! "q") [name! "a", name! "b"] .cascade .noAction]

/-- The row of {lit}`PRAGMA foreign_key_list` with the cells after {lit}`id` and {lit}`seq`. -/
def keyRow (id seq : Int) (table source : String) (target : Value) (onDelete : String) : List Value :=
  [.integer id, .integer seq, textValue table, textValue source, target, textValue "NO ACTION", textValue onDelete,
    textValue "NONE"]

-- The ids count the keys newest first: the table constraint is id 0. Without a column list,
-- to is NULL.
example : outputs [createC, .pragma (.foreignKeyList (name! "c"))] = [.done 0, .rows [
    keyRow 0 0 "q" "y" (textValue "a") "CASCADE", keyRow 0 1 "q" "z" (textValue "b") "CASCADE",
    keyRow 1 0 "p" "x" .null "NO ACTION"]] := by
  decide +kernel

/-- The source {lit}`function('argument')`. -/
def pragmaOf (function argument : String) : TableReference :=
  { table := .ofString function, alias := none, arguments := some [.string argument.toUTF8.toList] }

/-- {lit}`SELECT columns FROM function('argument') [WHERE filter]`. -/
def selectFrom (columns : List ResultColumn) (function argument : String) (filter : Option Expr := none) :
    Syntax.Statement :=
  .select columns (some (pragmaOf function argument)) [] filter [] [] none none

/-- The result column of a name. -/
def named (text : String) : ResultColumn := .expression (name text) none text

-- The table-valued form gives the same rows; * does not show the hidden arg and schema.
example : outputs [createW, selectFrom [.star] "pragma_table_info" "w"] = [.done 0, .rows [
    [.integer 0, textValue "a", textValue "", .integer 1, .null, .integer 2],
    [.integer 1, textValue "b", textValue "", .integer 1, .null, .integer 1]]] := by
  decide +kernel
example : outputs [createW, selectFrom [named "name"] "pragma_table_info" "w"
    (some (.compare .eq (name "pk") (.numeric "1")))] = [.done 0, .rows [[textValue "b"]]] := by
  decide +kernel

/-- {lit}`CREATE TABLE s(schema)`. -/
def createS : Syntax.Statement := .createTable (name! "s") [typed "schema" none] []

/-- {lit}`JOIN s USING (schema)`. -/
def usingSchema : Join :=
  { operator := [], source := { table := name! "s", alias := none, arguments := none }, condition := none,
    usingColumns := some [name! "schema"] }

/-- The kind of the restriction of the statement after {lit}`w` and {lit}`s` are created, or none
when it resolves. -/
def restrictionOf (statement : Syntax.Statement) : Option RestrictionKind :=
  match migration (catalogOf (migration [] [createW, createS])) [statement] with
  | .restricted restriction => some restriction.kind
  | .resolved .. => none

-- A name of arg or schema, in a condition, a result column, GROUP BY or USING, is the
-- restriction table-function, because SQLite gives a condition on it to the pragma.
example : restrictionOf (selectFrom [named "name"] "pragma_table_info" "w"
    (some (.compare .eq (name "schema") (.string "main".toUTF8.toList)))) = some .tableFunction := by decide +kernel
example : restrictionOf (selectFrom [named "arg"] "pragma_table_info" "w") = some .tableFunction := by decide +kernel
example : restrictionOf (.select [.expression (.callStar "count") none "count(*)"]
    (some (pragmaOf "pragma_table_info" "w")) [] none [name "schema"] [] none none) = some .tableFunction := by
  decide +kernel
example : restrictionOf (.select [.star] (some (pragmaOf "pragma_table_info" "s")) [usingSchema] none [] [] none
    none) = some .tableFunction := by decide +kernel
example : restrictionOf (selectFrom [named "name"] "pragma_table_info" "w") = none := by decide +kernel

-- A cell has no affinity: the text '5' of dflt_value is not the integer 5.
example : outputs [createT, selectFrom [named "name"] "pragma_table_info" "t"
    (some (.compare .eq (name "dflt_value") (.numeric "5")))] = [.done 0, .rows []] := by
  decide +kernel
example : outputs [createC, selectFrom [named "from"] "pragma_foreign_key_list" "c"
    (some (.compare .eq (name "id") (.numeric "1")))] = [.done 0, .rows [[textValue "x"]]] := by
  decide +kernel

-- Another table-valued pragma ends the run.
example : (outputs [selectFrom [.star] "pragma_index_list" "t"]).map Output.endsRun = [true] := by decide +kernel

end Belay.Sqlite.Model.PragmaSchemaExamples
