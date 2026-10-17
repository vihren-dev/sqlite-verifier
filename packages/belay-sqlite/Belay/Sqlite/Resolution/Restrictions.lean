set_option doc.verso true

/-! The registry of model restrictions. A model restriction is SQL that SQLite accepts
but the model does not describe; resolution refuses it, and the user reads its
message. Each restriction is one constructor of {lit}`RestrictionKind`, which names the
decision that introduced it. Its stable id and its message are in
{lit}`Belay.Sqlite.RestrictionText`, and {lit}`docs/semantic-subset.md` lists every id. -/

namespace Belay.Sqlite

/-- A model restriction of name resolution. The comment of each constructor says what
the model does not describe and which decision introduced the restriction. -/
inductive RestrictionKind where
  /-- A schema contains only CREATE TABLE and CREATE INDEX statements (ADR 0008). -/
  | schemaStatement
  /-- Engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled (ADR 0008). -/
  | engineTable
  /-- Column names {lit}`rowid`, {lit}`_rowid_` and {lit}`oid` are not modeled (ADR 0008). -/
  | rowidColumnName
  /-- Constraints and defaults in a CREATE TABLE that runs are not modeled (ADR 0008). -/
  | createTableConstraints
  /-- Only the {lit}`CURRENT_TIMESTAMP` default is modeled (ADR 0008). -/
  | unmodeledDefault
  /-- A CREATE INDEX that runs is not modeled (ADR 0008). -/
  | createIndexRuns
  /-- Only a nullable column without a default can be added (ADR 0008). -/
  | addColumnConstraint
  /-- Time values are not modeled (ADR 0008). -/
  | timeValue
  /-- A {lit}`SET` value that reads the row is not modeled for a column of a unique key
  (ADR 0012, amendment 1, owner decision on question 1). -/
  | rowDependentKey
  /-- {lit}`ON CONFLICT DO UPDATE` without a target on a table with more than one key:
  SQLite then chooses the key of the conflict by its internal order of indexes. -/
  | conflictWithoutTarget
  /-- Keys of one INSERT with different conflict algorithms other than REPLACE: SQLite's
  internal order of keys decides which one applies to a row that conflicts on both. -/
  | mixedConflictAlgorithms
  /-- UPDATE of a table with a constraint algorithm other than ABORT: {lit}`UPDATE OR` and
  the algorithms of UPDATE are not modeled (ADR 0012, amendment 4). -/
  | constraintAlgorithmUpdate
  /-- REPLACE of a NOT NULL column with a default: REPLACE stores the default for a NULL,
  and the model does not evaluate defaults in writes. -/
  | replaceDefault
  /-- A column named twice in INSERT is not modeled (ADR 0008). -/
  | insertColumnTwice
  /-- A column assigned twice in UPDATE is not modeled (ADR 0008). -/
  | updateColumnTwice
  /-- A rowid name ({lit}`rowid`, {lit}`_rowid_` or {lit}`oid`) that is not a column is
  not modeled in an expression: introduced for RETURNING in ADR 0012 slice 3a, and
  extended to queries and write expressions on 2026-10-14, where SQLite reads the
  rowid and the model would report {lit}`no such column`. -/
  | rowidName
  /-- A join operator other than {lit}`,`, {lit}`[INNER] JOIN`, {lit}`CROSS JOIN`,
  {lit}`LEFT [OUTER] JOIN`, {lit}`RIGHT [OUTER] JOIN` and {lit}`FULL [OUTER] JOIN`, each
  with an optional leading {lit}`NATURAL`, is not modeled, for example
  {lit}`OUTER LEFT JOIN` (ADR 0012, amendment 2). -/
  | joinOperator
  /-- Two sources of a query with the same name are not modeled (ADR 0012, amendment 2,
  owner decision on question 3). -/
  | duplicateSource
  /-- An {lit}`ON` condition that names a table joined after it is not modeled: SQLite
  resolves it against the whole {lit}`FROM`, and the model evaluates it while it joins
  (ADR 0012, amendment 2). -/
  | laterTableInOn
  /-- Queries of SQLite's own tables, such as {lit}`sqlite_schema`, are not modeled (ADR 0012 slice 1). -/
  | systemTable
  /-- Only {lit}`COUNT(*)`, {lit}`COUNT`, {lit}`MIN`, {lit}`MAX`, {lit}`SUM` and {lit}`AVG` of one argument, {lit}`COALESCE` of two or more arguments, and {lit}`json_extract` and the operators {lit}`->` and {lit}`->>` are modeled as functions (ADR 0012 slices 1, 2 and 6b). -/
  | unmodeledFunction
  /-- An aggregate inside an expression is not modeled (ADR 0012 slice 1). -/
  | aggregateInExpression
  /-- A result column alias inside WHERE or an ORDER BY expression is not modeled (ADR 0012 slice 1). -/
  | aliasInExpression
  /-- A value used as a condition is not modeled (ADR 0012 slice 1). -/
  | valueAsCondition
  /-- A comparison of columns with different kinds of affinity is not modeled (ADR 0012 slice 1). -/
  | mixedAffinityComparison
  /-- A text value compared with a numeric column would be converted to a number (ADR 0012 slice 1). -/
  | textToNumber
  /-- A number compared with a TEXT column would be converted to text (ADR 0012 slice 1). -/
  | numberToText
  /-- Only a column name or a result column number is modeled in GROUP BY (ADR 0012 slice 1). -/
  | groupByTerm
  /-- A result column outside GROUP BY in an aggregate query is not modeled (ADR 0012 slice 1). -/
  | bareColumn
  /-- An aggregate query is modeled with ORDER BY result column numbers or aliases only (ADR 0012 slice 1). -/
  | aggregateOrderBy
  /-- Only an integer literal is modeled as LIMIT or OFFSET (ADR 0012 slice 1). -/
  | windowValue
  /-- A negative OFFSET is not modeled (ADR 0012 slice 1). -/
  | negativeOffset
  /-- SUM in a grouped query with LIMIT or OFFSET is not modeled, because SQLite may stop before an overflowing group (ADR 0012 slice 2). -/
  | windowedGroupSum
  /-- A constant value in {lit}`VALUES` or {lit}`SET` whose JSON function fails is not modeled, because the model does not describe when SQLite evaluates it (ADR 0012 slice 6b). -/
  | constantFunctionError
  deriving Repr, DecidableEq

end Belay.Sqlite
