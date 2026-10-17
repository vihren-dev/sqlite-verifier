import Belay.Sqlite.Resolution.Resolved

set_option doc.verso true

/-! The text of SQLite's prepare errors. Each message fills the format that the
constructor of {name}`Belay.Sqlite.PrepareError` names with its arguments. Names
appear as written in the statement, as SQLite prints them. -/

namespace Belay.Sqlite

/-- An ordinal as SQLite's {lit}`%r` format writes it: {assert}`ordinal 1 = "1st"`,
{assert}`ordinal 12 = "12th"`, {assert}`ordinal 23 = "23rd"`. -/
def ordinal (number : Nat) : String :=
  let suffix := if number % 100 / 10 == 1 then "th" else match number % 10 with
    | 1 => "st" | 2 => "nd" | 3 => "rd" | _ => "th"
  s!"{number}{suffix}"

/-- SQLite's message for a prepare error, for example {lit}`no such table: t`. -/
def PrepareError.message : PrepareError → String
  | .reservedName name => s!"object name reserved for internal use: {name}"
  | .tableExists name => s!"table {name} already exists"
  | .indexNameUsed name => s!"there is already an index named {name}"
  | .tableNameUsed name => s!"there is already a table named {name}"
  | .indexExists name => s!"index {name} already exists"
  | .tooManyColumns table => s!"too many columns on {table}"
  | .duplicateColumn column => s!"duplicate column name: {column}"
  | .multiplePrimaryKeys table => s!"table \"{table}\" has more than one primary key"
  | .defaultNotConstant column => s!"default value of column [{column}] is not constant"
  | .noSuchTable name => s!"no such table: {name}"
  | .noSuchColumn name => s!"no such column: {name}"
  | .tableHasNoColumn table column => s!"table {table} has no column named {column}"
  | .valueCount table columns values => s!"table {table} has {columns} columns but {values} values were supplied"
  | .valuesForColumns values columns => s!"{values} values for {columns} columns"
  | .valuesDiffer => "all VALUES must have the same number of terms"
  | .tableMayNotBeAltered name => s!"table {name} may not be altered"
  | .tableMayNotBeIndexed name => s!"table {name} may not be indexed"
  | .cannotAddPrimaryKey => "Cannot add a PRIMARY KEY column"
  | .cannotAddUnique => "Cannot add a UNIQUE column"
  | .hexLiteralTooBig text => s!"hex literal too big: {text}"
  | .misuseOfAggregate function => s!"misuse of aggregate function {function}()"
  | .aggregateInGroupBy => "aggregate functions are not allowed in the GROUP BY clause"
  | .orderByOutOfRange term columns => s!"{ordinal term} ORDER BY term out of range - should be between 1 and {columns}"
  | .groupByOutOfRange term columns => s!"{ordinal term} GROUP BY term out of range - should be between 1 and {columns}"
  | .wrongArgumentCount function => s!"wrong number of arguments to function {function}()"
  | .ambiguousColumn name => s!"ambiguous column name: {name}"
  | .noSuchSource name => s!"no such table: {name}"
  | .tooManyTables => "at most 64 tables in a join"
  | .returningSourceStar => "RETURNING may not use \"TABLE.*\" wildcards"
  | .joinUsingColumn name => s!"cannot join using column {name} - column not present in both tables"
  | .naturalJoinCondition => "a NATURAL join may not have an ON or USING clause"
  | .ambiguousUsingReference name => s!"ambiguous reference to {name} in USING()"
  | .conflictTargetMismatch => "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"
  | .conflictingAlgorithms => "conflicting ON CONFLICT clauses specified"
  | .noTablesSpecified => "no tables specified"
  | .tooManyEachArguments => "too many arguments on json_each() - max 2"

end Belay.Sqlite
