import Belay.Sqlite.Model.Resolution.Examples
import Belay.Sqlite.Model.SqlExecution

set_option doc.verso true

/-! Examples of index forms (ADR 0014, slice 1), checked by {lit}`#guard` when the package
builds: the resolution of key terms, filters and sort orders, SQLite's prepare errors and
the model restrictions of index forms, and the execution of partial and expression unique
indexes and of a CREATE INDEX that runs. The authored corpus of index forms compares the
same rules with SQLite. -/

namespace Belay.Sqlite.Model.Resolution.IndexExamples

open Belay.Sqlite.Model Syntax Belay.Sqlite.Model.Resolution.Examples

/-- A table {lit}`d(a INTEGER, b TEXT)`. -/
def tableD : Catalog := catalogOf (migration [] [.createTable (name! "d") [column (name! "a") (some "INTEGER"), column (name! "b")] []])

/-- A CREATE INDEX of {lit}`d` with the key terms and the filter. -/
def indexD (terms : List OrderTerm) (filter : Option Expr := none) (unique : Bool := false) : Syntax.Statement :=
  .createIndex (name! "i") unique (name! "d") terms filter

/-- A key term of an expression, ascending. -/
def term (expression : Expr) : OrderTerm := { expression, descending := false }

/-- The index that the resolution of one CREATE INDEX of {lit}`d` adds, or none. -/
def indexOf (statement : Syntax.Statement) : Option CatalogIndex :=
  match statements (migration tableD [statement]) with
  | [.createIndex _ _ index] => some index
  | _ => none

/-- The prepare error of one CREATE INDEX of {lit}`d`, or none. -/
def errorOf (statement : Syntax.Statement) : Option PrepareError :=
  match statements (migration tableD [statement]) with
  | [.prepareError error] => some error
  | _ => none

-- A column name is a column key; any other term is an expression; DESC is kept.
#guard (indexOf (indexD [key (name! "b"), { expression := .identifier (name! "a") .none, descending := true }])).map
  (·.keys) == some [{ term := .column 1 }, { term := .column 0, descending := true }]
#guard (indexOf (indexD [term (.arithmetic .add (.identifier (name! "a") .none) (.numeric "1"))])).map
  (fun index => index.keys.map (·.term matches .expression _)) == some [true]
#guard (indexOf (indexD [term (.numeric "5")])).isSome
-- An unquoted TRUE is an expression, not a column.
#guard (indexOf (indexD [term (.identifier (name! "true") .none)])).map
  (fun index => index.keys.map (·.term matches .expression _)) == some [true]
-- A filter is a condition over the table, also with a qualified name.
#guard (indexOf (indexD [key (name! "a")] (some (.isNull (.qualified (name! "d") (name! "b")) true)))).map
  (·.filter.isSome) == some true

-- SQLite's prepare errors of index forms: terms before the filter.
#guard errorOf (indexD [key (name! "zz")] (some (.identifier (name! "yy") .none))) ==
  some (.expression (.noSuchColumn (name! "zz")))
#guard errorOf (indexD [key (name! "a")] (some (.identifier (name! "yy") .none))) ==
  some (.expression (.noSuchColumn (name! "yy")))
#guard errorOf (indexD [term (.qualified (name! "d") (name! "a"))]) == some (.expression .qualifiedIndexTerm)
#guard errorOf (indexD [term (.currentTime "CURRENT_TIMESTAMP")]) == some (.expression (.nondeterministicIndex false))
#guard errorOf (indexD [key (name! "a")] (some (.compare .gt (.identifier (name! "b") .none) (.currentTime "CURRENT_DATE")))) ==
  some (.expression (.nondeterministicIndex true))
#guard errorOf (indexD [key (name! "rowid")]) == some (.expression (.noSuchColumn (name! "rowid")))
#guard (errorOf (indexD [term (.call "count" [.identifier (name! "a") .none])])).isSome
#guard (PrepareError.expression .qualifiedIndexTerm).message == "the \".\" operator prohibited in index expressions"
#guard (PrepareError.expression (.nondeterministicIndex true)).message ==
  "non-deterministic functions prohibited in partial index WHERE clauses"

-- Model restrictions of index forms.
#guard reason (migration tableD [indexD [term (.string [97])]]) ==
  RestrictionKind.indexStringTerm.message
#guard reason (migration tableD [indexD [term (.call "date" [.identifier (name! "b") .none])]]) ==
  RestrictionKind.indexDateFunction.message
#guard reason (migration tableD [indexD [term (.call "json_extract" [.identifier (name! "b") .none, .string [36]])]]) ==
  RestrictionKind.indexJsonFunction.message

/-- Run a script from {lit}`tableD` with no rows: its outcome, or none for a restriction. -/
def run (script : List Syntax.Statement) : Option Outcome :=
  match migration tableD script with
  | .resolved resolved _ => some (runSql (bindValues resolved []) tableD.emptyDatabase)
  | .restricted _ => none

/-- The position and reason of a failure, or none. -/
def failure : Option Outcome → Option (Nat × ExecutionError)
  | some (.failure position reason _) => some (position, reason)
  | some (.success _) | some (.pending ..) | none => none

/-- The cells of the rows of {lit}`d` after a run that succeeds, or none. -/
def rowsOfD : Option Outcome → Option (List (List Value))
  | some (.success database) => (database.table 0).map fun table => table.rows.map (·.values)
  | some (.failure ..) | some (.pending ..) | none => none

/-- INSERT of one row into {lit}`d`. -/
def insertD (a : String) (b : Expr) : Syntax.Statement := .insert (name! "d") none [[.numeric a, b]] [] none []

/-- {lit}`b IS NOT NULL`. -/
def bPresent : Expr := .isNull (.identifier (name! "b") .none) true

-- A partial unique index admits two equal keys outside its filter and refuses two inside it.
#guard failure (run [indexD [key (name! "a")] (some bPresent) true, insertD "1" .null, insertD "1" .null]) == none
#guard failure (run [indexD [key (name! "a")] (some bPresent) true, insertD "1" (.string [120]), insertD "1" (.string [121])]) ==
  some (2, .constraintViolation)
#guard failure (run [indexD [key (name! "a")] (some bPresent) true, insertD "1" .null, insertD "1" (.string [121])]) == none
-- An expression index refuses rows equal under the expression.
#guard failure (run [indexD [term (.arithmetic .multiply (.identifier (name! "a") .none) (.numeric "0"))] none true,
  insertD "1" .null, insertD "2" .null]) == some (2, .constraintViolation)
-- A CREATE UNIQUE INDEX over rows that conflict fails and keeps the catalog.
#guard failure (run [insertD "1" .null, insertD "1" .null, indexD [key (name! "a")] none true]) ==
  some (2, .constraintViolation)
#guard rowsOfD (run [insertD "1" .null, insertD "1" .null, indexD [key (name! "a")] none]) ==
  some [[.integer 1, .null], [.integer 1, .null]]
-- REPLACE over a partial unique index replaces the row inside the filter.
#guard rowsOfD (run [indexD [key (name! "a")] (some bPresent) true, insertD "1" (.string [120]),
  .insert (name! "d") none [[.numeric "1", .string [121]]] [] (some .replace) []]) ==
  some [[.integer 1, .text [121]]]
-- An ON CONFLICT target names no partial index.
#guard (match statements (migration tableD [indexD [key (name! "a")] (some bPresent) true,
    .insert (name! "d") none [[.numeric "1", .null]] [{ target := some [name! "a"], action := .nothing }] none []]) with
  | [_, .prepareError (.expression .conflictTargetMismatch)] => true
  | _ => false)

-- A list of key terms with no term is SQLite's `near ")": syntax error`, as is an empty
-- PRIMARY KEY or UNIQUE list of CREATE TABLE.
#guard errorOf (indexD []) == some (.expression .emptyKeyList)
#guard statements (schema [.createTable (name! "e") [column (name! "a")] [.primaryKey [] ]]) ==
  [.prepareError (.expression .emptyKeyList)]
#guard statements (schema [.createTable (name! "e") [column (name! "a")] [.unique []]]) ==
  [.prepareError (.expression .emptyKeyList)]

end Belay.Sqlite.Model.Resolution.IndexExamples
