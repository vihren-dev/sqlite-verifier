import Belay.Sqlite.SqlExecution
import Belay.Sqlite.Resolution.Examples

set_option doc.verso true

/-! Checked examples of scripts that read the clock (ADR 0012, amendment 5, slice 6e2):
each statement sees the clock value of its position, a {lit}`DEFAULT CURRENT_TIMESTAMP`
column gets the value of the INSERT's clock, ADD COLUMN with that default fails on a
populated table, and a script without time keywords has one outcome at every clock
assignment. Each expected value was checked against native SQLite 3.51.0. -/

namespace Belay.Sqlite.ClockExamples
open Belay.Sqlite Syntax Resolution.Examples

/-- The text value with the UTF-8 bytes of a string, to write expected results. -/
def textOf (text : String) : Value := .text text.toUTF8.toList

/-- {lit}`2024-12-31 23:59:59.999` in Julian-day milliseconds. -/
def lastClockOf2024 : Int := 212602449599999

/-- {lit}`2025-01-01 00:00:00` in Julian-day milliseconds. -/
def firstClockOf2025 : Int := 212602449600000

/-- The clock assignment that gives the first statement {name}`lastClockOf2024` and every
later statement {name}`firstClockOf2025`. -/
def newYear : Clock := fun position => if position = 0 then lastClockOf2024 else firstClockOf2025

/-- A column with a declared type and a time keyword as its default, such as
{lit}`b INTEGER DEFAULT CURRENT_TIMESTAMP`. -/
def timeDefault (name : String) (declaredType : Option String) (keyword : String) : ColumnDefinition :=
  { name, declaredType, constraints := [.default (.currentTime keyword) keyword] }

/-- {lit}`CREATE TABLE t(a TEXT, b INTEGER DEFAULT CURRENT_TIMESTAMP)`. -/
def createT : Syntax.Statement :=
  .createTable "t" [column "a", timeDefault "b" (some "INTEGER") "CURRENT_TIMESTAMP"] []

/-- The catalog that {name}`createT` describes. -/
def catalogT : Catalog := catalogOf (schema [createT])

/-- The empty table of {name}`createT` at position 0. -/
def emptyT : Database := fun position =>
  if position = 0 then (catalogT.tableAt 0).map fun shape => { shape, rows := [] } else none

/-- The values of the rows of table 0 after a script, or none when it fails. -/
def rowsAfter (clock : Clock) (script : List Syntax.Statement) : Option (List (List Value)) :=
  match runSqlAt clock (statements (migration catalogT script)) emptyT with
  | .success database => (database 0).map (·.rows.map (·.values))
  | .failure .. | .pending .. => none

-- Two INSERTs see the clock values of their positions; the omitted column b gets the
-- timestamp of its own statement, and its INTEGER affinity keeps the text.
#guard rowsAfter newYear [.insert "t" (some ["a"]) [[.currentTime "CURRENT_DATE"]] [],
    .insert "t" (some ["a"]) [[.currentTime "CURRENT_TIME"]] []] ==
  some [[textOf "2024-12-31", textOf "2024-12-31 23:59:59"], [textOf "00:00:00", textOf "2025-01-01 00:00:00"]]
-- Every statement at one clock value gives one date.
#guard rowsAfter (fun _ => firstClockOf2025) [.insert "t" (some ["a"]) [[.currentTime "CURRENT_DATE"]] [],
    .insert "t" (some ["a"]) [[.currentTime "CURRENT_DATE"]] []] ==
  some [[textOf "2025-01-01", textOf "2025-01-01 00:00:00"], [textOf "2025-01-01", textOf "2025-01-01 00:00:00"]]
-- A clock of zero gives NULL for the keyword and the default.
#guard rowsAfter (fun _ => 0) [.insert "t" (some ["a"]) [[.currentTime "CURRENT_TIMESTAMP"]] []] ==
  some [[.null, .null]]

/-- The resolved script {lit}`INSERT INTO t(a, b) VALUES ('x', 1)`, which reads no clock. -/
def clockFree : List Resolved.Statement := [.insert 0 [[.text [120], .integer 1]] [] []]

-- It is the resolution of the statement.
#guard statements (migration catalogT [.insert "t" (some ["a", "b"]) [[.string [120], .numeric "1"]] []]) == clockFree

/-- For every clock assignment, {name}`clockFree` has the outcome of {name}`runSql`. -/
example (clock : Clock) : runSqlAt clock clockFree emptyT = runSql clockFree emptyT :=
  runSqlAt_of_readsClock clock clockFree emptyT (by decide)

-- ADD COLUMN with a time default fails on a populated table and succeeds on an empty one.
#guard (match runSqlAt (fun _ => firstClockOf2025) (statements (migration catalogT
    [.insert "t" (some ["a"]) [[.null]] [],
     .addColumn "t" (timeDefault "c" none "CURRENT_DATE")])) emptyT with
  | .failure 1 .nonConstantColumnDefault _ => true
  | .success _ | .failure .. | .pending .. => false)
#guard (match runSqlAt (fun _ => firstClockOf2025) (statements (migration catalogT
    [.addColumn "t" (timeDefault "c" none "CURRENT_DATE")])) emptyT with
  | .success _ => true
  | .failure .. | .pending .. => false)

end Belay.Sqlite.ClockExamples
