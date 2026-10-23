import Belay.Sqlite.Model.Resolution.Restrictions

set_option doc.verso true

/-! The stable ids and the messages of the model restrictions in
{name}`Belay.Sqlite.Model.RestrictionKind`. An id names the restriction in reports and in
{lit}`docs/semantic-subset.md`; it does not change when the message changes. -/

namespace Belay.Sqlite.Model

/-- The stable id of a restriction: lowercase words joined by hyphens. -/
def RestrictionKind.id : RestrictionKind → String
  | .schemaStatement => "schema-statement"
  | .engineTable => "engine-table"
  | .rowidColumnName => "rowid-column-name"
  | .unmodeledDefault => "unmodeled-default"
  | .indexStringTerm => "index-string-term"
  | .indexDateFunction => "index-date-function"
  | .indexJsonFunction => "index-json-function"
  | .unknownCollation => "unknown-collation"
  | .checkFunction => "check-function"
  | .addColumnCheckError => "add-column-check-error"
  | .generatedFunction => "generated-function"
  | .generatedLoop => "generated-loop"
  | .parameterErrorOrder => "parameter-error-order"
  | .upsertGenerated => "upsert-generated"
  | .addColumnGenerated => "add-column-generated"
  | .addColumnStrictType => "add-column-strict-type"
  | .dropConstraintIndex => "drop-constraint-index"
  | .addColumnConstraint => "add-column-constraint"
  | .rowDependentKey => "row-dependent-key"
  | .conflictWithoutTarget => "conflict-without-target"
  | .mixedConflictAlgorithms => "mixed-conflict-algorithms"
  | .constraintAlgorithmUpdate => "constraint-algorithm-update"
  | .replaceDefault => "replace-default"
  | .insertColumnTwice => "insert-column-twice"
  | .updateColumnTwice => "update-column-twice"
  | .rowidName => "rowid-name"
  | .joinOperator => "join-operator"
  | .laterTableInOn => "later-table-in-on"
  | .systemTable => "system-table"
  | .unmodeledFunction => "unmodeled-function"
  | .aggregateInExpression => "aggregate-in-expression"
  | .aliasInExpression => "alias-in-expression"
  | .groupByTerm => "group-by-term"
  | .bareColumn => "bare-column"
  | .aggregateOrderBy => "aggregate-order-by"
  | .windowValue => "window-value"
  | .negativeOffset => "negative-offset"
  | .windowedGroupSum => "windowed-group-sum"
  | .constantFunctionError => "constant-function-error"
  | .tableFunction => "table-function"
  | .functionJoin => "function-join"
  | .laterSourceInArguments => "later-source-in-arguments"
  | .jsonSubtype => "json-subtype"
  | .subqueryHere => "subquery-here"
  | .outerAggregate => "outer-aggregate"
  | .subqueryFallibleCall => "subquery-fallible-call"
  | .subqueryReadsTarget => "subquery-reads-target"
  | .distinctOrderBy => "distinct-order-by"
  | .deferredForeignKey => "deferred-foreign-key"
  | .foreignKeyUpsert => "foreign-key-upsert"
  | .raiseForm => "raise-form"
  | .triggerForm => "trigger-form"
  | .triggerWritesOwnTable => "trigger-writes-own-table"
  | .schemaTriggerOrder => "schema-trigger-order"
  | .compoundSubqueryColumn => "compound-subquery-column"
  | .compoundOrderByTerm => "compound-order-by-term"

/-- The message of a restriction that users read: what the model does not describe,
and what to write instead. -/
def RestrictionKind.message : RestrictionKind → String
  | .schemaStatement => "a schema contains only CREATE TABLE, CREATE INDEX and CREATE TRIGGER statements; move the other statement to the script"
  | .engineTable => "engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled; remove the table from the schema"
  | .rowidColumnName => "column names rowid, _rowid_ and oid are not modeled; rename the column"
  | .unmodeledDefault => "default expression is not modeled; use a literal default"
  | .indexStringTerm => "a string literal as an index key is not modeled; name the column without quotes"
  | .indexDateFunction => "a date and time function in an index key or WHERE clause is not modeled; index the column instead"
  | .indexJsonFunction => "a JSON function or another function that can fail, such as abs, like or unistr, in an index key or WHERE clause is not modeled; index the column instead"
  | .unknownCollation => "COLLATE with a name other than BINARY, NOCASE or RTRIM in an expression is not modeled; use one of these collations"
  | .checkFunction => "a time keyword, a date and time function, a JSON function or another function that can fail, such as abs, like or unistr, in a CHECK constraint is not modeled; check the column values instead"
  | .addColumnCheckError => "a CHECK of ADD COLUMN that names no column of the table, or uses an aggregate, is not modeled; correct the CHECK"
  | .generatedFunction => "a date and time function, a JSON function or another function that can fail, such as abs, like or unistr, in a generated column is not modeled; compute the value in the write"
  | .generatedLoop => "generated columns that read each other in a loop are not modeled; SQLite refuses the table"
  | .parameterErrorOrder => "a parameter in a CHECK constraint, a generated column or an index, in an expression with a function call, a subquery, a qualified name, a name that does not resolve, an unknown collation, IN () or AND with a number, is not modeled; remove the parameter, which SQLite refuses there unless it removes the expression first"
  | .upsertGenerated => "DO UPDATE of a generated column is not modeled; assign the columns that it reads"
  | .addColumnGenerated => "ADD COLUMN of a generated column is not modeled; create the table with it"
  | .addColumnStrictType => "ADD COLUMN to a STRICT table without one of its types, or with a default that does not fit the type, is not modeled; use INT, INTEGER, REAL, TEXT, BLOB or ANY and a default of that type"
  | .dropConstraintIndex => "DROP INDEX of a name that begins with sqlite_autoindex_ is not modeled; SQLite does not drop the index of a UNIQUE or PRIMARY KEY constraint"
  | .addColumnConstraint => "the default of the added column is not modeled; use a literal default or no default"
  | .rowDependentKey => "a SET value that reads the row is not modeled for a column of a unique key; assign a constant value"
  | .conflictWithoutTarget => "DO UPDATE without a conflict target is not modeled for a table with more than one key; name the target columns"
  | .mixedConflictAlgorithms => "keys with different conflict algorithms other than REPLACE are not modeled; use one algorithm, for example with INSERT OR"
  | .constraintAlgorithmUpdate => "UPDATE of a table with ON CONFLICT constraint algorithms is not modeled; remove the algorithms or use INSERT"
  | .replaceDefault => "REPLACE of a NOT NULL column with a default is not modeled; write the value instead of NULL"
  | .insertColumnTwice => "a column named twice in INSERT is not modeled; name each column once"
  | .updateColumnTwice => "a column assigned twice in UPDATE is not modeled; assign each column once"
  | .rowidName => "the rowid names rowid, _rowid_ and oid are not modeled in expressions over a table, or as the SET column of a table without an INTEGER PRIMARY KEY; name the table's columns"
  | .joinOperator => "this join operator is refused by SQLite and not modeled; write JOIN, LEFT JOIN or a comma"
  | .laterTableInOn => "an ON condition that names a table joined after it is not modeled; move the condition to WHERE or to the later join"
  | .systemTable => "queries of SQLite's own tables, such as sqlite_schema, are not modeled; query an application table"
  | .unmodeledFunction => "this function, or this form of it, is not modeled; rewrite the expression without it"
  | .aggregateInExpression => "an aggregate here is not modeled, such as the argument of a function that can fail; use the aggregate as a whole result column"
  | .aliasInExpression => "a result column alias inside WHERE or an ORDER BY expression is not modeled; write the column expression"
  | .groupByTerm => "only a column name or a result column number is modeled in GROUP BY"
  | .bareColumn => "a result column outside GROUP BY in an aggregate query is not modeled; group by it or aggregate it"
  | .aggregateOrderBy => "an ORDER BY term of an aggregate query that reads a column outside GROUP BY is not modeled; order by a grouping term, an aggregate or a result column"
  | .windowValue => "only an integer literal or a lone parameter is modeled as LIMIT or OFFSET; write an integer or ?"
  | .negativeOffset => "a negative literal OFFSET is not modeled; write OFFSET 0 or more, or bind the value to a parameter"
  | .windowedGroupSum => "SUM in a grouped query with LIMIT or OFFSET is not modeled, because SQLite may stop before an overflowing group; remove the window or the SUM"
  | .constantFunctionError => "a constant value in VALUES or SET whose function fails, such as malformed JSON or abs of the smallest integer, is not modeled; correct the arguments"
  | .tableFunction => "only json_each with one or two arguments is modeled as a table-valued function in FROM; use json_each or a table"
  | .functionJoin => "json_each as the right operand of RIGHT or FULL JOIN, with NATURAL or USING, or before a NATURAL JOIN, is not modeled; write JOIN or LEFT JOIN with ON"
  | .laterSourceInArguments => "an argument of json_each that reads a later source is not modeled; write the source before json_each"
  | .jsonSubtype => "a JSON value passed on through coalesce, iif, nullif, min or max is not modeled as a JSON function argument; pass the JSON call directly"
  | .subqueryHere => "a subquery is modeled only in a SELECT statement, outside ON conditions and json_each arguments; rewrite the statement without it"
  | .outerAggregate => "an aggregate in a subquery whose argument reads a column of an outer query is not modeled, because SQLite computes it in the outer query; aggregate only columns of the subquery's own tables"
  | .subqueryFallibleCall => "a SELECT without FROM that has both a subquery and a function that can fail is not modeled; select from a table or remove the function"
  | .subqueryReadsTarget => "a subquery of INSERT, UPDATE or DELETE that reads the written table is not modeled, because SQLite evaluates it while the statement changes the table; read the table in a separate statement"
  | .distinctOrderBy => "an ORDER BY expression of SELECT DISTINCT that is no result column is not modeled; order by a result column"
  | .deferredForeignKey => "with foreign keys on, a write that checks a DEFERRABLE INITIALLY DEFERRED foreign key is not modeled, because SQLite checks such keys at COMMIT; declare the key without INITIALLY DEFERRED"
  | .foreignKeyUpsert => "with foreign keys on, INSERT with ON CONFLICT DO UPDATE on a table with foreign keys to check is not modeled; write the UPDATE as a separate statement"
  | .raiseForm => "RAISE in a trigger is modeled only as the one result column of a SELECT without FROM, alone or as a result of CASE, with a message that cannot fail; write SELECT RAISE(...) WHERE condition or SELECT CASE WHEN condition THEN RAISE(...) END"
  | .triggerForm => "a trigger with ON CONFLICT DO UPDATE in its body, with a function that can fail in a write of its body, with a WHEN condition that has a function that can fail or a subquery, or with too many triggers that fire each other, and ON CONFLICT DO UPDATE on a table with a trigger, are not modeled; move the work into separate statements"
  | .triggerWritesOwnTable => "a BEFORE UPDATE or BEFORE DELETE trigger that writes its own table is not modeled, because SQLite documents the result as undefined; use an AFTER trigger"
  | .schemaTriggerOrder => "two triggers of one table, time and event in the starting schema are not modeled, because the schema does not say which one SQLite runs first; create them in the script"
  | .compoundSubqueryColumn => "x IN (q) and a scalar subquery (q) are not modeled when q is a compound SELECT with an operator other than UNION ALL and an ORDER BY term with COLLATE, because SQLite then reads the column of a derived table; remove the COLLATE from the ORDER BY of q"
  | .compoundOrderByTerm => "this ORDER BY term of a compound SELECT is not modeled, because the model cannot match it with a result column as SQLite does, or SQLite then names a result column at random; order by a result column number or an AS alias, and give the columns different names"

/-- Every restriction, in the order of the registry. -/
def RestrictionKind.all : List RestrictionKind :=
  [.schemaStatement, .engineTable, .rowidColumnName, .unmodeledDefault, .indexStringTerm, .indexDateFunction, .indexJsonFunction, .unknownCollation, .checkFunction, .addColumnCheckError, .generatedFunction, .generatedLoop, .parameterErrorOrder, .upsertGenerated, .addColumnGenerated, .addColumnStrictType, .dropConstraintIndex, .addColumnConstraint, .rowDependentKey, .conflictWithoutTarget, .mixedConflictAlgorithms, .constraintAlgorithmUpdate, .replaceDefault, .insertColumnTwice, .updateColumnTwice, .rowidName, .joinOperator, .laterTableInOn, .systemTable, .unmodeledFunction, .aggregateInExpression, .aliasInExpression, .groupByTerm, .bareColumn, .aggregateOrderBy, .windowValue, .negativeOffset, .windowedGroupSum, .constantFunctionError, .tableFunction, .functionJoin, .laterSourceInArguments, .jsonSubtype, .subqueryHere, .outerAggregate, .subqueryFallibleCall, .subqueryReadsTarget, .distinctOrderBy, .deferredForeignKey, .foreignKeyUpsert, .raiseForm, .triggerForm, .triggerWritesOwnTable, .schemaTriggerOrder,
    .compoundSubqueryColumn, .compoundOrderByTerm]

/-- For every restriction, it is in {name}`RestrictionKind.all`. Proof sketch: case
analysis on the restriction. -/
theorem RestrictionKind.mem_all (kind : RestrictionKind) : kind ∈ RestrictionKind.all := by
  cases kind <;> simp [RestrictionKind.all]

-- The ids are distinct.
#guard (RestrictionKind.all.map RestrictionKind.id).eraseDups.length == RestrictionKind.all.length

end Belay.Sqlite.Model
