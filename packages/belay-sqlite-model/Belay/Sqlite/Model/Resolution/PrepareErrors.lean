import Belay.Sqlite.Model.Identifier
import Belay.Sqlite.Model.Operators

set_option doc.verso true

/-! The errors that {lit}`sqlite3_prepare_v2` reports for a statement (ADR 0013, D8) that
name no catalog object ({lit}`ExprError`), which the resolution of expressions and clauses
gives. {lit}`PrepareError` (in {lit}`StatementPrepareError`) carries them. -/

namespace Belay.Sqlite.Model

/-- An error that {lit}`sqlite3_prepare_v2` reports that names no catalog object: an error
of an expression, a clause or a definition, such as a name that is missing or ambiguous,
a misused function, a term out of range, a duplicate column, or a form that SQLite
refuses. {lit}`PrepareError.expression` carries them; resolution of expressions
({lit}`ValueIssue`) can give only these. -/
inductive ExprError where
  /-- {lit}`object name reserved for internal use: %s` ({lit}`sqlite3CheckObjectName`). -/
  | reservedName (name : Identifier)
  /-- {lit}`too many columns on %s` ({lit}`sqlite3AddColumn`). -/
  | tooManyColumns (table : Identifier)
  /-- {lit}`duplicate column name: %s` ({lit}`sqlite3AddColumn`). -/
  | duplicateColumn (column : Identifier)
  /-- {lit}`table "%s" has more than one primary key` ({lit}`sqlite3AddPrimaryKey`). -/
  | multiplePrimaryKeys (table : Identifier)
  /-- {lit}`default value of column [%s] is not constant` ({lit}`sqlite3AddDefaultValue`). -/
  | defaultNotConstant (column : Identifier)
  /-- {lit}`table %S has no column named %s` (INSERT column list). -/
  | tableHasNoColumn (table column : Identifier)
  /-- {lit}`table %S has %d columns but %d values were supplied` (INSERT). -/
  | valueCount (table : Identifier) (columns values : Nat)
  /-- {lit}`%d values for %d columns` (INSERT with a column list). -/
  | valuesForColumns (values columns : Nat)
  /-- {lit}`all VALUES must have the same number of terms` ({lit}`sqlite3MultiValues`). -/
  | valuesDiffer
  /-- {lit}`table %s may not be altered` ({lit}`isAlterableTable`). -/
  | tableMayNotBeAltered (name : Identifier)
  /-- {lit}`table %s may not be indexed` ({lit}`sqlite3CreateIndex`). -/
  | tableMayNotBeIndexed (name : Identifier)
  /-- {lit}`Cannot add a PRIMARY KEY column` ({lit}`sqlite3AlterFinishAddColumn`). -/
  | cannotAddPrimaryKey
  /-- {lit}`PRIMARY KEY missing on table %s`: a {lit}`WITHOUT ROWID` table without a primary
  key ({lit}`sqlite3EndTable`). -/
  | primaryKeyMissing (table : Identifier)
  /-- {lit}`Cannot add a UNIQUE column` ({lit}`sqlite3AlterFinishAddColumn`). -/
  | cannotAddUnique
  /-- {lit}`conflicting ON CONFLICT clauses specified`: two constraints of one index with
  different explicit {lit}`ON CONFLICT` algorithms. -/
  | conflictingAlgorithms
  /-- {lit}`no such column: %s` (name resolution of an expression or key). -/
  | noSuchColumn (name : Identifier)
  /-- {lit}`no such collation sequence: %s`: a {lit}`COLLATE` name other than {lit}`BINARY`,
  {lit}`NOCASE` and {lit}`RTRIM` (ADR 0014, D3). -/
  | noSuchCollation (name : Identifier)
  /-- {lit}`foreign key on %s should reference only one column of table %T`: a column's
  {lit}`REFERENCES` with more than one referenced column (ADR 0014, slice 4). -/
  | foreignKeyOneColumn (column table : Identifier)
  /-- {lit}`number of columns in foreign key does not match the number of columns in the
  referenced table`: a {lit}`FOREIGN KEY` with a column list of another length. -/
  | foreignKeyColumnCount
  /-- {lit}`unknown column "%s" in foreign key definition`: a {lit}`FOREIGN KEY` column that
  the table does not have. -/
  | unknownForeignKeyColumn (name : Identifier)
  /-- {lit}`cannot INSERT into generated column "%s"` (ADR 0014, slice 5). -/
  | insertGenerated (name : Identifier)
  /-- {lit}`cannot UPDATE generated column "%s"`. -/
  | updateGenerated (name : Identifier)
  /-- {lit}`generated columns cannot be part of the PRIMARY KEY`. -/
  | generatedInPrimaryKey
  /-- {lit}`cannot use DEFAULT on a generated column`: a DEFAULT after {lit}`AS`. -/
  | defaultOnGenerated
  /-- {lit}`error in generated column "%s"`: {lit}`AS` after a DEFAULT. -/
  | errorInGenerated (name : Identifier)
  /-- {lit}`non-deterministic functions prohibited in generated columns`: a time keyword. -/
  | nondeterministicGenerated
  /-- {lit}`must have at least one non-generated column`: a table whose columns are all
  generated. -/
  | onlyGeneratedColumns
  /-- {lit}`the "." operator prohibited in generated columns`: a qualified name in the
  expression of a generated column. -/
  | qualifiedGenerated
  /-- {lit}`unknown datatype for %s.%s: "%s"`: a column of a {lit}`STRICT` table whose type is
  none of the six (ADR 0014, slice 6). -/
  | unknownDatatype (table column : Identifier) (type : String)
  /-- {lit}`missing datatype for %s.%s`: a column of a {lit}`STRICT` table without a type. -/
  | missingDatatype (table column : Identifier)
  /-- {lit}`the "." operator prohibited in index expressions`: a qualified name in a key
  term of CREATE INDEX ({lit}`notValidImpl`). -/
  | qualifiedIndexTerm
  /-- {lit}`non-deterministic functions prohibited in index expressions`, or
  {lit}`... in partial index WHERE clauses` when {lit}`filter` holds:
  {lit}`CURRENT_TIME`, {lit}`CURRENT_DATE` or {lit}`CURRENT_TIMESTAMP` in a key term or in
  the filter of CREATE INDEX. -/
  | nondeterministicIndex (filter : Bool)
  /-- {lit}`hex literal too big: %s` (a hexadecimal literal with more than 16 digits). -/
  | hexLiteralTooBig (text : String)
  /-- {lit}`misuse of aggregate function %s()` (an aggregate in {lit}`WHERE`, or one
  aggregate inside another; {lit}`resolveSelectStep`). -/
  | misuseOfAggregate (function : String)
  /-- {lit}`aggregate functions are not allowed in the GROUP BY clause`. -/
  | aggregateInGroupBy
  /-- {lit}`%r ORDER BY term out of range - should be between 1 and %d`: the one-based
  term and the number of result columns ({lit}`resolveOrderGroupBy`). -/
  | orderByOutOfRange (term columns : Nat)
  /-- {lit}`%r GROUP BY term out of range - should be between 1 and %d`. -/
  | groupByOutOfRange (term columns : Nat)
  /-- {lit}`wrong number of arguments to function %s()`, with the function name as
  written ({lit}`resolveExprStep`). -/
  | wrongArgumentCount (function : String)
  /-- {lit}`no such function: %s`, for a name that names no function of the library, as
  written ({lit}`resolveExprStep`; ADR 0015, D1). -/
  | noSuchFunction (function : String)
  /-- {lit}`second argument to likelihood() must be a constant between 0.0 and 1.0`: the
  second argument is no REAL literal of at most 1.0 ({lit}`exprProbability`). -/
  | likelihoodArgument
  /-- {lit}`ambiguous column name: %s`: an unqualified name that names a column of two or
  more sources of a join, as written. -/
  | ambiguousColumn (name : Identifier)
  /-- {lit}`no such table: %s` for {lit}`source.*` with a name that names no source of
  the query, as written. Unlike {lit}`PrepareError.noSuchTable`, it names no catalog
  object. -/
  | noSuchSource (name : Identifier)
  /-- {lit}`at most 64 tables in a join`. -/
  | tooManyTables
  /-- {lit}`RETURNING may not use "TABLE.*" wildcards`: a {lit}`source.*` column in
  {lit}`RETURNING`, for every source name. -/
  | returningSourceStar
  /-- {lit}`cannot join using column %s - column not present in both tables`: a name of
  {lit}`USING` that is not a column of both the left input and the joined table, as
  written. -/
  | joinUsingColumn (name : Identifier)
  /-- {lit}`a NATURAL join may not have an ON or USING clause`. -/
  | naturalJoinCondition
  /-- {lit}`ambiguous reference to %s in USING()`: in a {lit}`FROM` with a right or full
  join, a merged name of which a left table after the first has a column that its own
  join does not merge, as written. -/
  | ambiguousUsingReference (name : Identifier)
  /-- {lit}`ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint`: a
  target whose columns are not the columns of one key of the table. -/
  | conflictTargetMismatch
  /-- {lit}`no tables specified`: {lit}`*` in a {lit}`SELECT` without {lit}`FROM`. -/
  | noTablesSpecified
  /-- {lit}`too many arguments on json_each() - max 2`: a {lit}`json_each` source in
  {lit}`FROM` with three or more arguments. -/
  | tooManyEachArguments
  /-- {lit}`sub-select returns %d columns - expected 1`: a scalar subquery or the subquery of
  {lit}`IN` with another number of result columns, with that number ({lit}`sqlite3SubselectError`;
  in a comparison SQLite reports {lit}`row value misused`, with the same error code). -/
  | subqueryColumns (count : Nat)
  /-- {lit}`HAVING clause on a non-aggregate query`: {lit}`HAVING` in a query without
  {lit}`GROUP BY` and without an aggregate (ADR 0018, D3). -/
  | havingNonAggregate
  /-- {lit}`RAISE() may only be used within a trigger-program`: {lit}`RAISE` in a statement that
  is no trigger's (ADR 0018, D5). -/
  | raiseOutsideTrigger
  /-- {lit}`cannot create trigger on system table`: CREATE TRIGGER on a table whose name begins
  with {lit}`sqlite_` (ADR 0018, D5). -/
  | triggerOnSystemTable
  /-- {lit}`parameters prohibited in CHECK constraints`: a parameter in a CHECK constraint
  (ADR 0019, D1). -/
  | parameterInCheck
  /-- {lit}`parameters prohibited in generated columns`: a parameter in the expression of a
  generated column. -/
  | parameterInGenerated
  /-- {lit}`parameters prohibited in index expressions`, or
  {lit}`... in partial index WHERE clauses` when {lit}`filter` holds: a parameter in a key term
  or in the filter of CREATE INDEX. -/
  | parameterInIndex (filter : Bool)
  /-- {lit}`trigger cannot use variables`: a parameter anywhere in CREATE TRIGGER. -/
  | triggerVariables
  /-- {lit}`SELECTs to the left and right of %s do not have the same number of result columns`:
  two terms of a compound {lit}`SELECT` with a different number of result columns, with the
  operator between them ({lit}`sqlite3SelectWrongNumTermsError`; ADR 0019, D3). -/
  | compoundColumns (operator : CompoundOperator)
  /-- {lit}`%r ORDER BY term does not match any column in the result set`: an {lit}`ORDER BY`
  term of a compound {lit}`SELECT` that names no result column, with the one-based term
  ({lit}`resolveCompoundOrderBy`). -/
  | orderByNoMatch (term : Nat)
  deriving Repr, DecidableEq

end Belay.Sqlite.Model
