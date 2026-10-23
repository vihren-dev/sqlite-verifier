set_option doc.verso true

/-! The registry of model restrictions. A model restriction is SQL that SQLite accepts but the model does
not describe; resolution refuses it, and the user reads its message. Each restriction is one constructor
of {lit}`RestrictionKind`, which names the decision that introduced it. Its stable id and its message
are in {lit}`Belay.Sqlite.Model.RestrictionText`, and {lit}`docs/semantic-subset.md` lists every id. -/

namespace Belay.Sqlite.Model

/-- A model restriction of name resolution. The comment of each constructor says what
the model does not describe and which decision introduced the restriction. -/
inductive RestrictionKind where
  /-- A schema contains only CREATE TABLE, CREATE INDEX and CREATE TRIGGER statements (ADR 0008; ADR 0018, D5). -/
  | schemaStatement
  /-- Engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled (ADR 0008). -/
  | engineTable
  /-- Column names {lit}`rowid`, {lit}`_rowid_` and {lit}`oid` are not modeled (ADR 0008). -/
  | rowidColumnName
  /-- Only literal defaults and {lit}`CURRENT_TIMESTAMP` are modeled (ADR 0008, T14). -/
  | unmodeledDefault
  /-- A string literal as a key term of CREATE INDEX, also a double-quoted name that is no
  column: SQLite reads a string that names a column as that column (ADR 0014, slice 1). -/
  | indexStringTerm
  /-- A date and time function in a key term or the filter of CREATE INDEX: SQLite refuses
  one that reads the clock only when it writes a row (ADR 0014, slice 1). -/
  | indexDateFunction
  /-- A JSON function in a key term or the filter of CREATE INDEX: it can fail while a row
  is written, which the model's key check does not describe (ADR 0014, slice 1). -/
  | indexJsonFunction
  /-- A {lit}`COLLATE` in an expression with a name that names no collation: SQLite looks
  the name up only where it uses the collation, and its query planner decides some of
  those uses, so the model cannot tell whether the statement fails (ADR 0014, slice 3). -/
  | unknownCollation
  /-- A time keyword, a date and time function or a JSON function in a CHECK constraint: the
  first two can give another value on each evaluation, and the last can fail while a row is
  written, which the model's check does not describe (ADR 0014, slice 4). -/
  | checkFunction
  /-- A CHECK of ADD COLUMN that SQLite cannot resolve: SQLite reports it while the statement
  runs, as {lit}`error in table %s after add column: %s`, which the model does not describe
  (ADR 0014, slice 4). -/
  | addColumnCheckError
  /-- A date and time function or a JSON function in a generated column: SQLite refuses
  {lit}`'now'` only when it writes a row, and a JSON function can fail while a row is written
  (ADR 0014, slice 5). -/
  | generatedFunction
  /-- Generated columns that read each other in a loop: SQLite reports it while CREATE TABLE runs. -/
  | generatedLoop
  /-- A parameter where SQLite prohibits one, in an expression where SQLite's walk of names can
  also find another error: which error SQLite reports depends on the walk (ADR 0019, D1). -/
  | parameterErrorOrder
  /-- A {lit}`DO UPDATE` that assigns a generated column: SQLite refuses it only when a row conflicts. -/
  | upsertGenerated
  /-- ADD COLUMN of a generated column: SQLite computes a {lit}`VIRTUAL` one for every
  existing row and refuses a {lit}`STORED` one while the statement runs, which the model
  does not describe. -/
  | addColumnGenerated
  /-- ADD COLUMN to a {lit}`STRICT` table with a type that it does not admit, or with a
  default that does not fit the type: SQLite reports it while the statement runs, which the
  model does not describe (ADR 0014, slice 6). -/
  | addColumnStrictType
  /-- DROP INDEX of a name that begins with {lit}`sqlite_autoindex_` and is no catalog index:
  the catalog does not name the indexes of UNIQUE and PRIMARY KEY constraints, which SQLite
  refuses to drop (ADR 0014, slice 7). -/
  | dropConstraintIndex
  /-- The added column requires unmodeled default evaluation. -/
  | addColumnConstraint
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
  rowid and the model would report {lit}`no such column`. As the column of a {lit}`SET`
  assignment it assigns the rowid alias; for a table without one it is this restriction, since a
  resolved write has no assignment of the physical rowid (2026-10-21). -/
  | rowidName
  /-- A join operator that SQLite refuses with {lit}`unknown join type`, such as
  {lit}`INNER OUTER JOIN`, is not modeled: the model has no such prepare error (ADR 0012,
  amendment 2; ADR 0013, amendment 2). -/
  | joinOperator
  /-- An {lit}`ON` condition that names a source joined after it is not modeled: SQLite
  moves it to {lit}`WHERE` for a {lit}`FROM` without outer joins and refuses it otherwise,
  with a prepare error that the model does not have (ADR 0012, amendment 2; ADR 0013,
  amendment 2). -/
  | laterTableInOn
  /-- Queries of SQLite's own tables, such as {lit}`sqlite_schema`, are not modeled (ADR 0012 slice 1). -/
  | systemTable
  /-- A function of the pinned library that the model does not describe, or a form of it that it does not describe, such as a window function (ADR 0012 slices 1, 2, 6b and 6c; ADR 0015). -/
  | unmodeledFunction
  /-- An aggregate where the model does not describe it is not modeled, such as the argument of a
  call that can fail, whose faults the model's scan reads without the aggregate's value (ADR 0012
  slice 1; ADR 0018, slice 3, models the other aggregates inside expressions). -/
  | aggregateInExpression
  /-- A result column alias inside WHERE or an ORDER BY expression is not modeled (ADR 0012 slice 1). -/
  | aliasInExpression
  /-- Only a column name or a result column number is modeled in GROUP BY (ADR 0012 slice 1). -/
  | groupByTerm
  /-- A result column outside GROUP BY in an aggregate query is not modeled (ADR 0012 slice 1). -/
  | bareColumn
  /-- An {lit}`ORDER BY` term of an aggregate query that reads a column outside the grouping terms
  is not modeled (ADR 0012 slice 1; ADR 0018, slice 3). -/
  | aggregateOrderBy
  /-- Only an integer literal is modeled as LIMIT or OFFSET (ADR 0012 slice 1). -/
  | windowValue
  /-- A negative literal OFFSET is not modeled (ADR 0012 slice 1); a negative bound OFFSET is 0. -/
  | negativeOffset
  /-- SUM in a grouped query with LIMIT or OFFSET is not modeled, because SQLite may stop before an overflowing group (ADR 0012 slice 2). -/
  | windowedGroupSum
  /-- A constant value in {lit}`VALUES` or {lit}`SET` whose JSON function fails is not modeled, because the model does not describe when SQLite evaluates it (ADR 0012 slice 6b). -/
  | constantFunctionError
  /-- Only {lit}`json_each` with one or two arguments, and two pragmas with one text literal and no
  name of {lit}`arg` or {lit}`schema`, are modeled in {lit}`FROM` (ADR 0012 slice 6d; ADR 0019, D2). -/
  | tableFunction
  /-- A table-valued function as the right operand of a right or full join, or with
  {lit}`NATURAL` or {lit}`USING`, and a {lit}`NATURAL` join after one, are not modeled: a
  correlated source has no fixed rows to keep unmatched, and {lit}`NATURAL` skips hidden
  columns (ADR 0012 slice 6d; ADR 0013, amendment 2). -/
  | functionJoin
  /-- An argument of {lit}`json_each` that reads a later source is not modeled: SQLite
  evaluates it only because its planner reorders inner joins, and the model joins in
  written order (ADR 0012 slice 6d; ADR 0013, amendment 2). -/
  | laterSourceInArguments
  /-- An argument of a JSON function that reads it as SQL value, such as a value of
  {lit}`json_array` or the operand of {lit}`json_group_array`, is not modeled when it passes on a JSON call through {lit}`COALESCE`,
  {lit}`iif`, {lit}`nullif`, {lit}`min` or {lit}`max`: SQLite keeps the JSON subtype through such
  expressions, which the model does not describe (ADR 0015, slice 3). -/
  | jsonSubtype
  /-- A subquery outside the expressions of a {lit}`SELECT` that the model resolves, such as in an
  {lit}`ON` condition, a {lit}`json_each` argument or another statement, is not modeled
  (ADR 0018, slice 1). -/
  | subqueryHere
  /-- An aggregate in a subquery whose argument reads a cell of a query around it is not
  modeled: SQLite computes an aggregate whose argument reads only outer columns in the outer
  query (checked natively: {lit}`SELECT (SELECT count(t.k) FROM u) FROM t` gives one row)
  (ADR 0018, slice 1). -/
  | outerAggregate
  /-- A query without {lit}`FROM` that has both a subquery and a call that can fail is not
  modeled: the model reports a certain failure of such a query, which a value of the subquery
  that SQLite's plan chooses could avoid (ADR 0018, slice 1). -/
  | subqueryFallibleCall
  /-- A subquery of a write that reads the written table is not modeled: SQLite evaluates an
  uncorrelated subquery once, but a correlated one over the rows that the statement has
  already changed, in the order in which it writes them (ADR 0018, slice 1). -/
  | subqueryReadsTarget
  /-- An {lit}`ORDER BY` expression of {lit}`SELECT DISTINCT` that is no result column is not
  modeled: SQLite sorts each kept row by the value of a row that its plan chooses (ADR 0018,
  slice 3). -/
  | distinctOrderBy
  /-- With foreign keys on, a write that processes a foreign key that is
  {lit}`DEFERRABLE INITIALLY DEFERRED` is not modeled: SQLite counts its violations across the
  statements of the transaction and checks the count at {lit}`COMMIT` (ADR 0018, slice 4). -/
  | deferredForeignKey
  /-- With foreign keys on, an INSERT with {lit}`ON CONFLICT DO UPDATE` whose table has a
  foreign key to check is not modeled: SQLite checks the keys of the updated row as an UPDATE
  does (ADR 0018, slice 4). -/
  | foreignKeyUpsert
  /-- {lit}`RAISE` in a trigger outside the one result column of a SELECT without
  {lit}`FROM`, where it is the column or a result of its {lit}`CASE`, and a {lit}`RAISE` whose
  message can fail, are not modeled: the model evaluates {lit}`RAISE` only where SQLite certainly
  reaches it in a known order (ADR 0018, slice 5). -/
  | raiseForm
  /-- A trigger form that the model does not describe: {lit}`ON CONFLICT DO UPDATE` in its
  body, a write of its body or a {lit}`WHEN` condition with a call that can fail, a {lit}`WHEN`
  condition with a subquery, triggers that fire each
  other past the bound of the resolution, and {lit}`ON CONFLICT DO UPDATE` on a table with a
  trigger, whose UPDATE triggers the resolution does not follow (ADR 0018, slice 5). -/
  | triggerForm
  /-- A {lit}`BEFORE UPDATE` or {lit}`BEFORE DELETE` trigger whose program writes the table of
  its own event, directly or through the triggers and foreign-key actions that it fires, is not
  modeled: SQLite documents the result of the update or delete as undefined (ADR 0018,
  slice 5). -/
  | triggerWritesOwnTable
  /-- Two triggers of one table, time and event in the starting schema are not modeled: the
  case record lists the schema in name order, so it does not say which trigger SQLite created
  last and runs first (ADR 0018, slice 5). -/
  | schemaTriggerOrder
  /-- {lit}`x IN (q)` and a scalar {lit}`(q)` over a compound {lit}`SELECT` that SQLite sorts as {lit}`SELECT * FROM (compound)`, because an operator is not {lit}`UNION ALL` and an {lit}`ORDER BY` term has {lit}`COLLATE`, are not modeled: they read the column of that derived table (ADR 0019, D3). -/
  | compoundSubqueryColumn
  /-- An {lit}`ORDER BY` term of a compound {lit}`SELECT` that the model cannot match with a result column as SQLite does is not modeled: an aggregate, an expression that is a result expression of a term after resolution but not as written, or a {lit}`COLLATE` term after which SQLite gives a result column a random name (ADR 0019, D3). -/
  | compoundOrderByTerm
  /-- {lit}`PRAGMA foreign_key_check` without a table name when two or more tables have a mismatch:
  SQLite reports the first one in the order of its schema hash table (ADR 0019, D2). -/
  | foreignKeyMismatchOrder
  deriving Repr, DecidableEq

end Belay.Sqlite.Model
