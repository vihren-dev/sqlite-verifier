import Belay.Sqlite.Resolution.Restrictions

set_option doc.verso true

/-! The stable ids and the messages of the model restrictions in
{name}`Belay.Sqlite.RestrictionKind`. An id names the restriction in reports and in
{lit}`docs/semantic-subset.md`; it does not change when the message changes. -/

namespace Belay.Sqlite

/-- The stable id of a restriction: lowercase words joined by hyphens. -/
def RestrictionKind.id : RestrictionKind → String
  | .schemaStatement => "schema-statement"
  | .engineTable => "engine-table"
  | .rowidColumnName => "rowid-column-name"
  | .createTableConstraints => "create-table-constraints"
  | .unmodeledDefault => "unmodeled-default"
  | .createIndexRuns => "create-index-runs"
  | .addColumnConstraint => "add-column-constraint"
  | .timeValue => "time-value"
  | .rowDependentKey => "row-dependent-key"
  | .conflictWithoutTarget => "conflict-without-target"
  | .mixedConflictAlgorithms => "mixed-conflict-algorithms"
  | .constraintAlgorithmUpdate => "constraint-algorithm-update"
  | .replaceDefault => "replace-default"
  | .insertColumnTwice => "insert-column-twice"
  | .updateColumnTwice => "update-column-twice"
  | .rowidName => "rowid-name"
  | .joinOperator => "join-operator"
  | .duplicateSource => "duplicate-source"
  | .laterTableInOn => "later-table-in-on"
  | .systemTable => "system-table"
  | .unmodeledFunction => "unmodeled-function"
  | .aggregateInExpression => "aggregate-in-expression"
  | .aliasInExpression => "alias-in-expression"
  | .valueAsCondition => "value-as-condition"
  | .mixedAffinityComparison => "mixed-affinity-comparison"
  | .textToNumber => "text-to-number"
  | .numberToText => "number-to-text"
  | .groupByTerm => "group-by-term"
  | .bareColumn => "bare-column"
  | .aggregateOrderBy => "aggregate-order-by"
  | .windowValue => "window-value"
  | .negativeOffset => "negative-offset"
  | .windowedGroupSum => "windowed-group-sum"
  | .constantFunctionError => "constant-function-error"
  | .tableFunction => "table-function"
  | .tableAfterFunction => "table-after-function"
  | .functionJoin => "function-join"
  | .laterSourceInArguments => "later-source-in-arguments"

/-- The message of a restriction that users read: what the model does not describe,
and what to write instead. -/
def RestrictionKind.message : RestrictionKind → String
  | .schemaStatement => "a schema contains only CREATE TABLE and CREATE INDEX statements; move the other statement to the script"
  | .engineTable => "engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled; remove the table from the schema"
  | .rowidColumnName => "column names rowid, _rowid_ and oid are not modeled; rename the column"
  | .createTableConstraints => "constraints and defaults in a CREATE TABLE that runs are not modeled; create the table with plain columns"
  | .unmodeledDefault => "default expression is not modeled; use a literal default"
  | .createIndexRuns => "a CREATE INDEX that runs is not modeled; remove the CREATE INDEX statement"
  | .addColumnConstraint => "the default of the added column is not modeled; use a literal default or no default"
  | .timeValue => "time values are not modeled; write the time as a text literal"
  | .rowDependentKey => "a SET value that reads the row is not modeled for a column of a unique key; assign a constant value"
  | .conflictWithoutTarget => "DO UPDATE without a conflict target is not modeled for a table with more than one key; name the target columns"
  | .mixedConflictAlgorithms => "keys with different conflict algorithms other than REPLACE are not modeled; use one algorithm, for example with INSERT OR"
  | .constraintAlgorithmUpdate => "UPDATE of a table with ON CONFLICT constraint algorithms is not modeled; remove the algorithms or use INSERT"
  | .replaceDefault => "REPLACE of a NOT NULL column with a default is not modeled; write the value instead of NULL"
  | .insertColumnTwice => "a column named twice in INSERT is not modeled; name each column once"
  | .updateColumnTwice => "a column assigned twice in UPDATE is not modeled; assign each column once"
  | .rowidName => "the rowid names rowid, _rowid_ and oid are not modeled in expressions over a table; name the table's columns"
  | .joinOperator => "this join operator is not modeled; write JOIN, LEFT JOIN or a comma"
  | .duplicateSource => "two sources of a query with the same name are not modeled; give each source its own alias"
  | .laterTableInOn => "an ON condition that names a table joined after it is not modeled; move the condition to WHERE or to the later join"
  | .systemTable => "queries of SQLite's own tables, such as sqlite_schema, are not modeled; query an application table"
  | .unmodeledFunction => "only COUNT(*), COUNT, MIN, MAX, SUM and AVG of one argument, COALESCE of two or more arguments, json_extract, ->, ->>, json_type, json_valid, json_array_length and json are modeled as functions"
  | .aggregateInExpression => "an aggregate inside an expression is not modeled; use the aggregate as a whole result column"
  | .aliasInExpression => "a result column alias inside WHERE or an ORDER BY expression is not modeled; write the column expression"
  | .valueAsCondition => "a value used as a condition is not modeled; write a comparison"
  | .mixedAffinityComparison => "a comparison of columns with different kinds of affinity is not modeled; compare columns with the same kind"
  | .textToNumber => "a text value compared with a numeric column would be converted to a number; write a number"
  | .numberToText => "a number compared with a TEXT column would be converted to text; write a text value"
  | .groupByTerm => "only a column name or a result column number is modeled in GROUP BY"
  | .bareColumn => "a result column outside GROUP BY in an aggregate query is not modeled; group by it or aggregate it"
  | .aggregateOrderBy => "an aggregate query is modeled with ORDER BY result column numbers or aliases only"
  | .windowValue => "only an integer literal is modeled as LIMIT or OFFSET; write an integer"
  | .negativeOffset => "a negative OFFSET is not modeled; write OFFSET 0 or more"
  | .windowedGroupSum => "SUM in a grouped query with LIMIT or OFFSET is not modeled, because SQLite may stop before an overflowing group; remove the window or the SUM"
  | .constantFunctionError => "a constant value in VALUES or SET whose JSON function fails is not modeled; correct the JSON text or the path"
  | .tableFunction => "only json_each with one or two arguments is modeled as a table-valued function in FROM; use json_each or a table"
  | .tableAfterFunction => "a table after json_each in FROM is not modeled; write the tables before json_each"
  | .functionJoin => "only an inner join without NATURAL or USING is modeled with json_each; write a comma, JOIN or JOIN ... ON"
  | .laterSourceInArguments => "an argument of json_each that reads a later source is not modeled; write the source before json_each"

/-- Every restriction, in the order of the registry. -/
def RestrictionKind.all : List RestrictionKind :=
  [.schemaStatement, .engineTable, .rowidColumnName, .createTableConstraints, .unmodeledDefault, .createIndexRuns, .addColumnConstraint, .timeValue, .rowDependentKey, .conflictWithoutTarget, .mixedConflictAlgorithms, .constraintAlgorithmUpdate, .replaceDefault, .insertColumnTwice, .updateColumnTwice, .rowidName, .joinOperator, .duplicateSource, .laterTableInOn, .systemTable, .unmodeledFunction, .aggregateInExpression, .aliasInExpression, .valueAsCondition, .mixedAffinityComparison, .textToNumber, .numberToText, .groupByTerm, .bareColumn, .aggregateOrderBy, .windowValue, .negativeOffset, .windowedGroupSum, .constantFunctionError, .tableFunction, .tableAfterFunction, .functionJoin, .laterSourceInArguments]

/-- For every restriction, it is in {name}`RestrictionKind.all`. Proof sketch: case
analysis on the restriction. -/
theorem RestrictionKind.mem_all (kind : RestrictionKind) : kind ∈ RestrictionKind.all := by
  cases kind <;> simp [RestrictionKind.all]

-- The ids are distinct.
#guard (RestrictionKind.all.map RestrictionKind.id).eraseDups.length == RestrictionKind.all.length

end Belay.Sqlite
