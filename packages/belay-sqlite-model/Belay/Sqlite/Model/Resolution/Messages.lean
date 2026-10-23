import Belay.Sqlite.Model.Resolution.Resolved

set_option doc.verso true

/-! The text of SQLite's prepare errors. Each message fills the format that the
constructor of {name}`Belay.Sqlite.Model.PrepareError` or {name}`Belay.Sqlite.Model.ExprError` names with its arguments. Names
appear as written in the statement, as SQLite prints them. -/

namespace Belay.Sqlite.Model

/-- An ordinal as SQLite's {lit}`%r` format writes it: {assert}`ordinal 1 = "1st"`,
{assert}`ordinal 12 = "12th"`, {assert}`ordinal 23 = "23rd"`. -/
def ordinal (number : Nat) : String :=
  let suffix := if number % 100 / 10 == 1 then "th" else match number % 10 with
    | 1 => "st" | 2 => "nd" | 3 => "rd" | _ => "th"
  s!"{number}{suffix}"

/-- SQLite's message for an error that names no catalog object, for example
{lit}`no such column: a`. -/
def ExprError.message : ExprError → String
  | .reservedName name => s!"object name reserved for internal use: {name}"
  | .tooManyColumns table => s!"too many columns on {table}"
  | .duplicateColumn column => s!"duplicate column name: {column}"
  | .multiplePrimaryKeys table => s!"table \"{table}\" has more than one primary key"
  | .defaultNotConstant column => s!"default value of column [{column}] is not constant"
  | .tableHasNoColumn table column => s!"table {table} has no column named {column}"
  | .valueCount table columns values => s!"table {table} has {columns} columns but {values} values were supplied"
  | .valuesForColumns values columns => s!"{values} values for {columns} columns"
  | .valuesDiffer => "all VALUES must have the same number of terms"
  | .tableMayNotBeAltered name => s!"table {name} may not be altered"
  | .tableMayNotBeIndexed name => s!"table {name} may not be indexed"
  | .cannotAddPrimaryKey => "Cannot add a PRIMARY KEY column"
  | .primaryKeyMissing table => s!"PRIMARY KEY missing on table {table}"
  | .cannotAddUnique => "Cannot add a UNIQUE column"
  | .conflictingAlgorithms => "conflicting ON CONFLICT clauses specified"
  | .noSuchColumn name => s!"no such column: {name}"
  | .noSuchCollation name => s!"no such collation sequence: {name}"
  | .foreignKeyOneColumn column table => s!"foreign key on {column} should reference only one column of table {table}"
  | .foreignKeyColumnCount => "number of columns in foreign key does not match the number of columns in the referenced table"
  | .unknownForeignKeyColumn name => s!"unknown column \"{name}\" in foreign key definition"
  | .insertGenerated name => s!"cannot INSERT into generated column \"{name}\""
  | .updateGenerated name => s!"cannot UPDATE generated column \"{name}\""
  | .generatedInPrimaryKey => "generated columns cannot be part of the PRIMARY KEY"
  | .defaultOnGenerated => "cannot use DEFAULT on a generated column"
  | .errorInGenerated name => s!"error in generated column \"{name}\""
  | .nondeterministicGenerated => "non-deterministic functions prohibited in generated columns"
  | .onlyGeneratedColumns => "must have at least one non-generated column"
  | .qualifiedGenerated => "the \".\" operator prohibited in generated columns"
  | .unknownDatatype table column type => s!"unknown datatype for {table}.{column}: \"{type}\""
  | .missingDatatype table column => s!"missing datatype for {table}.{column}"
  | .qualifiedIndexTerm => "the \".\" operator prohibited in index expressions"
  | .nondeterministicIndex filter =>
    "non-deterministic functions prohibited in " ++ (if filter then "partial index WHERE clauses" else "index expressions")
  | .hexLiteralTooBig text => s!"hex literal too big: {text}"
  | .misuseOfAggregate function => s!"misuse of aggregate function {function}()"
  | .aggregateInGroupBy => "aggregate functions are not allowed in the GROUP BY clause"
  | .orderByOutOfRange term columns => s!"{ordinal term} ORDER BY term out of range - should be between 1 and {columns}"
  | .orderByNoMatch term => s!"{ordinal term} ORDER BY term does not match any column in the result set"
  | .compoundColumns operator =>
    s!"SELECTs to the left and right of {operator.keywords} do not have the same number of result columns"
  | .groupByOutOfRange term columns => s!"{ordinal term} GROUP BY term out of range - should be between 1 and {columns}"
  | .wrongArgumentCount function => s!"wrong number of arguments to function {function}()"
  | .noSuchFunction function => s!"no such function: {function}"
  | .likelihoodArgument => "second argument to likelihood() must be a constant between 0.0 and 1.0"
  | .ambiguousColumn name => s!"ambiguous column name: {name}"
  | .noSuchSource name => s!"no such table: {name}"
  | .tooManyTables => "at most 64 tables in a join"
  | .returningSourceStar => "RETURNING may not use \"TABLE.*\" wildcards"
  | .joinUsingColumn name => s!"cannot join using column {name} - column not present in both tables"
  | .naturalJoinCondition => "a NATURAL join may not have an ON or USING clause"
  | .ambiguousUsingReference name => s!"ambiguous reference to {name} in USING()"
  | .conflictTargetMismatch => "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"
  | .noTablesSpecified => "no tables specified"
  | .tooManyEachArguments => "too many arguments on json_each() - max 2"
  | .subqueryColumns count => s!"sub-select returns {count} columns - expected 1"
  | .havingNonAggregate => "HAVING clause on a non-aggregate query"
  | .raiseOutsideTrigger => "RAISE() may only be used within a trigger-program"
  | .triggerOnSystemTable => "cannot create trigger on system table"
  | .parameterInCheck => "parameters prohibited in CHECK constraints"
  | .parameterInGenerated => "parameters prohibited in generated columns"
  | .parameterInIndex filter =>
    "parameters prohibited in " ++ (if filter then "partial index WHERE clauses" else "index expressions")
  | .triggerVariables => "trigger cannot use variables"

/-- A name as SQLite's {lit}`%w` writes it inside double quotes: each double quote doubled. -/
def quotedName (name : Identifier) : String :=
  String.join ((toString name).toList.map fun character => if character == '"' then "\"\"" else character.toString)

/-- SQLite's message for a prepare error, for example {lit}`no such table: t`. -/
def PrepareError.message : PrepareError → String
  | .tableExists name => s!"table {name} already exists"
  | .indexNameUsed name => s!"there is already an index named {name}"
  | .tableNameUsed name => s!"there is already a table named {name}"
  | .indexExists name => s!"index {name} already exists"
  | .noSuchTable name => s!"no such table: {name}"
  | .noSuchIndex name => s!"no such index: {name}"
  | .tableMayNotBeDropped name => s!"table {name} may not be dropped"
  | .noSuchReferencedTable name => s!"no such table: main.{name}"
  | .noSuchTrigger name => s!"no such trigger: {name}"
  | .triggerExists name => s!"trigger {name} already exists"
  | .foreignKeyMismatch child parent =>
    s!"foreign key mismatch - \"{quotedName child}\" referencing \"{quotedName parent}\""
  | .expression error => error.message

end Belay.Sqlite.Model
