# Supported subset

The model handles SQL in three layers (ADR 0008). The frontend maps the pinned
SQLite syntax tree to statement syntax. Lean resolves the syntax against the
catalog. The execution semantics runs the resolved statements. Each layer has a
boundary of its own.

## Statement syntax

The frontend maps these statements, and refuses every other statement as
`UNSUPPORTED` at its byte range:

- `CREATE TABLE` with column definitions (name, declared type text, `NOT NULL`,
  `PRIMARY KEY` with its sort order, `UNIQUE`, `COLLATE` (ADR 0014, slice 3), `CHECK`
  and `REFERENCES` (slice 4), `[GENERATED ALWAYS] AS (expr) [VIRTUAL | STORED]` (slice 5),
  and `DEFAULT` with a literal, a signed number, a time keyword or a name), table `PRIMARY KEY` and `UNIQUE` constraints over plain column
  names, `CHECK` and `FOREIGN KEY` (slice 4), `CONSTRAINT name` before any constraint,
  and the options `WITHOUT ROWID` (slice 2) and `STRICT` (slice 6);
- `CREATE [UNIQUE] INDEX` with key terms, each a column name or an expression with
  an optional `ASC` or `DESC`, and an optional `WHERE` filter (ADR 0014, slice 1);
- `ALTER TABLE … ADD [COLUMN]` with one column definition;
- `DROP TABLE [IF EXISTS] name` and `DROP INDEX [IF EXISTS] name` (ADR 0014, slice 7);
- `BEGIN` (optionally `DEFERRED`), `COMMIT`/`END` and `ROLLBACK`, optionally with
  `TRANSACTION`;
- `INSERT INTO table [(columns)] VALUES` with one or more rows;
- `UPDATE table SET column = value, … [WHERE expression]`;
- `DELETE FROM table [WHERE expression]`, which removes each row for which the
  expression is true (slice 3c);
- `RETURNING columns` after `INSERT … VALUES`, `UPDATE` and `DELETE`, with result
  columns as in `SELECT`, over each written or deleted row (slices 3a and 3c); an
  aggregate and `source.*` are SQLite's prepare errors, and a rowid name in
  `RETURNING` is a model restriction;
- `SELECT columns FROM tables [WHERE …] [GROUP BY …] [ORDER BY … [ASC|DESC]]
  [LIMIT n [OFFSET m]]`, whose result columns are `*`, `source.*` or expressions
  with an optional alias (ADR 0012, slice 1). Without `FROM`, the source is one row
  with no columns (slice 6a), which `WHERE` keeps or removes; aggregation, grouping,
  `ORDER BY` and `LIMIT` then apply as for any query, so `SELECT count(*) WHERE 0` is one
  row with 0. `LIMIT ?` and `OFFSET ?` read the bound value when the query starts, LIMIT
  first and OFFSET only when the LIMIT is not 0, and convert it as SQLite's
  `OP_MustBeInt` does; a value that is not an integer then fails the statement with
  `datatype mismatch`. A negative LIMIT has no limit, and a negative bound OFFSET skips
  no rows (ADR 0019). `*` is SQLite's `no tables specified`. `FROM` is one table, or tables joined
  left to right with `,`, `JOIN`, `INNER JOIN`, `CROSS JOIN` (with an optional `ON`)
  and `LEFT [OUTER] JOIN … ON`, and `RIGHT [OUTER] JOIN` and `FULL [OUTER] JOIN`
  with an optional `ON` (slice 4c), which add each right row that no row of the left
  tables matches, with NULL in their columns; each table may have an alias (`t AS x` or `t x`), and
  a column may be qualified as `source.column` (slice 4). An unqualified name that
  names a column of two sources is SQLite's `ambiguous column name`. An inner or left
  join may have `USING (columns)` instead of `ON`, or start with `NATURAL`
  (slice 4b): the join compares each named column, or each column name of the joined
  table that the left tables also have, with the left-most such left column, and `*`
  and unqualified names no longer see the right column of each pair. A `USING` name
  that is not in both inputs and `NATURAL` with `ON` or `USING` are SQLite's prepare
  errors. In a right join a merged name is the right column, with its affinity, and in
  a full join the coalesce of both, which has no affinity; in a query with a right or
  full join, each generated condition compares the coalesce of every left column of the
  name, and a left table that does not merge the name is SQLite's
  `ambiguous reference to a in USING()`; `*` and `x.*` of a table left of a right or
  full join show such a merged name (slice 4d).
- Subqueries in the expressions of a `SELECT` (ADR 0018, slice 1): `EXISTS (q)`, `NOT
  EXISTS (q)`, `x IN (q)`, `x NOT IN (q)` and the scalar subquery `(q)`, where `q` is a
  `SELECT` as above and may name the columns of the queries around it. A name resolves in
  its own query first, then outward. `EXISTS` is 1 or 0; a scalar subquery is the first
  value of its first row, or NULL without a row, and has the affinity of its result
  column; `IN` compares under the affinity and collation of its operand and the
  subquery's result column, and is NULL when no row matches and the subquery gives a
  NULL. A scalar subquery or `IN` subquery with another number of result columns than
  one is SQLite's `sub-select returns N columns - expected 1`. When rows tie, SQLite's
  plan can choose the first row of a scalar subquery and the rows of an `IN` window, so
  the model describes the statement only when every permitted order gives the same
  values. The values of `INSERT`, the `SET` values and the `WHERE` of `UPDATE`, and the
  `WHERE` of `DELETE` may have subqueries too, which read the database before the write; a
  subquery that reads the written table is a restriction. A subquery in an `ON` condition, a
  `json_each` argument, `RETURNING`, `ON CONFLICT` or a schema statement, and in `FROM`, is
  refused or a restriction.
- Compound `SELECT` (ADR 0019, D3): `UNION ALL`, `UNION`, `INTERSECT` and `EXCEPT` of
  `SELECT` terms as above, from left to right, as a statement and as the `q` of `EXISTS`,
  `IN` and a scalar subquery. Two rows are equal when each column compares equal under the
  compound column's collation, without affinity, and NULL equals NULL; the collation of a
  column is that of the left-most term whose expression has one, else `BINARY`. The columns
  have the names of the left-most term; when SQLite sorts the compound as
  `SELECT * FROM (compound)` (an operator other than `UNION ALL` and an `ORDER BY` term with
  `COLLATE`), they have the names of that subquery's columns, such as `a` for `a COLLATE NOCASE`
  and `a:1` for a second column `a`. `ORDER BY`, `LIMIT` and `OFFSET` apply to the whole
  compound; an `ORDER BY` term is a column number, an `AS` alias of a term or an expression
  equal to a result expression of a term, else SQLite's prepare error. `x IN (q)` reads the
  affinity and the collation of the right-most term's column, and a scalar `(q)` its affinity.
  When rows that are equal differ, such as `'a'` and `'A'` under `NOCASE`, SQLite's plan
  chooses the row that `UNION` keeps, and the statement is not described. A `VALUES` term, a
  compound in `FROM`, as an `INSERT` source and as a statement of a trigger body are refused.

Expressions are `NULL`, numeric, string and blob literals, the time keywords,
names, unary `-` and `+`, and `=`. Inside a `SELECT`, they may also be the other
comparisons, `IS` and `IS NOT`, `AND`, `OR`, `NOT`, `IS NULL` and its forms,
parentheses, `COUNT(*)`, `COUNT`, `MIN`, `MAX`, `SUM` and `AVG` of one argument, the arithmetic
operators `+`, `-`, `*`, `/` and `%`, unary `-` and `+` of any expression,
`CAST(expression AS type)`, and `COALESCE` of two or more arguments (ADR 0012,
slice 2), `x [NOT] IN (values)`, also with an empty list, which compares under the affinity
and the collation of `x` (a list of one constant value is SQLite's `x = +c`), `x [NOT]
BETWEEN a AND b` as `x >= a AND x <= b`, `CASE` with and without a base (a base compares as
`=` does), and `x || y`, NULL with a NULL operand (ADR 0018, slice 2), aggregates inside the
expressions of the result columns, `HAVING` and `ORDER BY` of a query, such as `count(*) + 1`,
`HAVING` with and without `GROUP BY`, and `SELECT DISTINCT`, which keeps one row of each set of
equal rows; when the rows of such a set differ, the statement is not described (ADR 0018,
slice 3), `json_extract` with one or more paths and the operators `->` and `->>`
(slice 6b), `json_type`, `json_valid`, `json_array_length` and `json` (slice 6c), and
`date`, `time`, `datetime`, `julianday`, `unixepoch` and `strftime` with one time value
or none, which is `now` (slice 6f), and any modifiers, in UTC (slice 6g). ADR 0015,
slice 1, adds the text and type functions `typeof`, `length`, `octet_length`, `lower`,
`upper`, `substr`, `substring`, `instr`, `replace`, `trim`, `ltrim`, `rtrim`, `hex`, `unhex`,
`quote`, `unistr`, `unistr_quote`, `char`, `unicode`, `concat`, `concat_ws`, `ifnull`,
`nullif`, `iif`, `if`, `likely`, `unlikely`, `likelihood`, scalar `min` and `max`, `abs`,
`sign`, `zeroblob`, `like` and `glob`, and the operators `LIKE`, `NOT LIKE`, `GLOB` and
`NOT GLOB` with an optional `ESCAPE`, which are calls of `like` and `glob` with the pattern
first, as in SQLite. Each follows SQLite's `func.c`: text counts UTF-8 characters, `lower`
and `upper` change ASCII letters only, and `LIKE` ignores ASCII case only. A function result
has no affinity. A name that is no function of the pinned library is SQLite's prepare error
`no such function`, and a number of arguments that the function does not accept is `wrong
number of arguments to function`; both come after the errors of the arguments. A
function that can fail while the statement runs, such as `abs` of the smallest integer or a
`LIKE` with an `ESCAPE` of two characters, fails as SQLite does in a query without `FROM`; in a
CHECK constraint, an index key or a generated column it is a model restriction, as a JSON
function is. ADR 0015, slice 2, adds the exact numeric functions `round`, `floor`, `ceil`,
`ceiling`, `trunc`, `sqrt`, `pi`, `degrees`, `radians` and `mod`, which follow SQLite's
`func.c` with the results of the C library for these exact operations, including the sign of
zero (`trunc(-0.5)` is `-0.0`); the transcendental functions (`ln`, `exp`, `pow`, `sin` and
the others) stay `unmodeled-function`. ADR 0015, slice 3, adds the JSON functions
`json_quote`, `json_array`, `json_object`, `json_set`, `json_insert`, `json_replace`,
`json_remove`, `json_patch`, `json_pretty` and `json_error_position`, and the aggregates
`json_group_array` and `json_group_object` of a whole result column. They write an SQL value as
SQLite's `jsonAppendSqlValue` does, and read a text value as JSON only when it has SQLite's JSON
subtype: when it is a direct call of `json`, `->`, one of these functions (except `json_pretty`
and `json_error_position`), or `json_extract` that selects an array or an object or has two or
more paths. A JSON call passed on through `coalesce`, `iif`, `nullif`, `min` or `max` is the
restriction `json-subtype`, also as the operand of a JSON aggregate. The position that `json_error_position` gives for malformed JSON
is not modeled. ADR 0015, slice 4, adds JSONB: `jsonb`, `jsonb_extract`, `jsonb_array`,
`jsonb_object`, `jsonb_set`, `jsonb_insert`, `jsonb_replace`, `jsonb_remove`, `jsonb_patch`,
`jsonb_group_array` and `jsonb_group_object` give SQLite's JSONB BLOB byte for byte, and every
JSON function reads a BLOB argument as SQLite does: JSONB when it passes SQLite's quick check,
else JSON text, and as a stored value the error `JSON cannot hold BLOB values`. The model reads
JSONB that is valid and in the encoding that SQLite's encoder gives for its tree; other JSONB,
such as a BLOB with a header longer than needed, is outside the supported subset. ADR 0015,
slice 5, adds the aggregates `group_concat(x [, separator])`, `string_agg(x, separator)` and
`total(x)` of a whole result column: `group_concat` joins the text of the values that are not
NULL in the order of the group's rows, each after the first preceded by the separator of its own
row, and `total` is the REAL sum of `SUM`'s summation, `0.0` for an empty group. ADR 0015,
slice 6, adds `printf` and `format` with every conversion, flag, width and precision of SQLite's
`sqlite3_str_vappendf` for SQL functions; a width or precision above 100000 is outside the
supported subset. A
`FROM` may end with `json_each(json [, path])` sources, joined by a comma or an inner
`JOIN` with an optional `ON` condition, whose arguments read the sources before them
(slice 6d). A comparison applies SQLite's comparison affinity (ADR 0013, D4): with an
INTEGER, REAL or NUMERIC operand, text that looks like a number compares as that number;
with a TEXT column and no affinity on the other side, a number compares as its text. Any
value is a condition: an integer or REAL is true when it is not zero, and text or a blob
when its numeric prefix is not zero, so `'1ab'` is true and `'abc'` is not. In a write, a
`VALUES` item may be any of these expressions that names no
column: resolution computes its value (slice 3a). A `SET` value may be any of these
expressions over the table's columns, evaluated on the old row, and the `WHERE` of an
`UPDATE` any condition of a `SELECT` (slice 3b). Each written value is then stored as SQLite
stores it in a column of that affinity (slice 3b): for example, the text `'12'`
becomes the integer 12 in an INTEGER column, and an integer becomes text in a TEXT
column. A unique key may have columns of any affinity (slice 5a): two rows conflict when
no key cell is NULL and each pair of stored cells is equal under SQLite's BINARY
comparison, so `1` and `1.0` conflict, while `'a'` and `'A'`, and `1` and `'1'`, do not.
An `INSERT ... VALUES` may have `ON CONFLICT` clauses (slice 5c): `DO NOTHING`, or
`DO UPDATE SET ... [WHERE ...]` whose values read the existing row by its column names
and the proposed row as `excluded.c`. A target is a list of column names, in any order,
that are the columns of one key. The rows are handled in order: the first clause whose
target key has a conflicting row handles the row, and a row that no clause handles is
inserted and checked against every key. A `DO UPDATE` without target on a table with
more than one key is the restriction `conflict-without-target`. `INSERT OR ROLLBACK`,
`ABORT`, `FAIL`, `IGNORE` and `REPLACE`, and `REPLACE INTO`, apply the algorithm to every
key and NOT NULL failure of a row (slice 5d): FAIL keeps the earlier rows, IGNORE skips
the row, REPLACE deletes every row that conflicts on any key (a NULL in a NOT NULL column
is ABORT), and ROLLBACK rolls back the open transaction. A rowid alias mismatch and the
row of `DO UPDATE` are always ABORT. In the schema, a `PRIMARY KEY`, `UNIQUE` or
`NOT NULL` constraint may have `ON CONFLICT algorithm`, its algorithm when INSERT has no
`OR` clause; keys with different algorithms other than REPLACE are the restriction
`mixed-conflict-algorithms`, UPDATE of such a table is `constraint-algorithm-update`, and
REPLACE of a NOT NULL column with a default is `replace-default`. `UPDATE OR`, a target with a direction, collation,
`NULLS` order, qualified name or `WHERE`, `WITH`, `FROM` in writes, sort modifiers in keys,
partial and expression indexes, `IF NOT EXISTS`, `TEMP`, schema names, table
options, `AS SELECT`, views, `TEMP` and `INSTEAD OF` triggers, virtual tables, `EXPLAIN`, `PRAGMA`,
`DISTINCT` inside an aggregate call, subqueries and table-valued functions in
`FROM`, schema-qualified tables and columns, `NULLS FIRST` and `NULLS LAST`, and
other functions are refused. Names keep
their case as written; quotes are removed as SQLite removes them. Numeric literals
keep their text, and declared types keep their text as SQLite's `sqlite3AddColumn` leaves
it: without a trailing `GENERATED ALWAYS` (ADR 0014, slice 5), then dequoted.

Every command retains its original half-open UTF-8 byte span; semicolons in names
and trigger bodies cannot split commands. An empty starting schema is allowed.

## Schema description

`schema.sql` describes the starting catalog. It may contain only `CREATE TABLE`,
`CREATE INDEX` and `CREATE TRIGGER`, in an order that SQLite can run: an index or a trigger
follows its table.
A schema statement that SQLite refuses to prepare, for example a second table
with the same name, is `INPUT_ERROR` with SQLite's message. The description may
contain keys, `NOT NULL`, literal defaults, time keyword defaults, indexes and
the exact native `sqlite_stat1` and `sqlite_stat4` tables, and `INTEGER PRIMARY KEY` rowid
aliases (slice 5b): the column is the rowid; INSERT of NULL or no value gives the next
rowid, another value must be an integer after INTEGER affinity, else SQLite's
`datatype mismatch`, and UPDATE of the alias moves the row. Other defaults and other
reserved names are model restrictions.
Omitted INSERT columns use their literal defaults and column affinities. A column
with `DEFAULT CURRENT_TIMESTAMP`, `CURRENT_DATE` or `CURRENT_TIME` gives an omitted
value the text of the INSERT's clock value, stored with the column affinity (slice 6e2).

An index has key terms and an optional `WHERE` filter (ADR 0014, slice 1). A term that
is a column name is that column; any other term is an expression over the table's
row. A unique index constrains only the rows for which its filter is true, and two
rows conflict when every term is equal and none is NULL. A `CREATE INDEX` in the
migration builds the index over the existing rows; a unique index over rows that
conflict fails with SQLite's constraint error and leaves the catalog unchanged. An
`ON CONFLICT` target names only a key of columns without a filter. SQLite's prepare
errors apply: a qualified name in a term, `CURRENT_TIME`, `CURRENT_DATE` and
`CURRENT_TIMESTAMP` in a term or the filter, and an aggregate. A string literal as a
term, a date and time function, a JSON function and a rowid name in the filter are
model restrictions.

A `WITHOUT ROWID` table (ADR 0014, slice 2) needs a primary key, else SQLite's
`PRIMARY KEY missing on table t`. Its key columns are NOT NULL, `INTEGER PRIMARY KEY` is
no rowid alias, and `rowid`, `_rowid_` and `oid` that name no column are
`no such column`. A full scan returns its rows in primary-key order, descending for
`PRIMARY KEY DESC`, and UPDATE and DELETE with `RETURNING` return them in that order; a
table with a rowid returns them in rowid order.

A CHECK constraint (ADR 0014, slice 4) is a condition over a row of its table, resolved
when the table is defined, after the other checks of the definition, with SQLite's prepare
errors: `no such column`, an aggregate as misuse, and the profile's `DQS_DDL`. INSERT,
UPDATE and `DO UPDATE` check each written row: NOT NULL first, then CHECK, then the unique
keys. A CHECK fails when its condition is false, read as a number; NULL passes. A failure
is SQLite's constraint error with the statement's `OR` algorithm, else ABORT: IGNORE skips
the row, REPLACE acts as ABORT, and SQLite ignores the conflict clause of a table CHECK.
ADD COLUMN with a CHECK checks the existing rows with the new default and fails with
result code 1 when one fails. A time keyword, a date and time function or a JSON function
in a CHECK is the restriction `check-function`, and a CHECK of ADD COLUMN that SQLite
cannot resolve is `add-column-check-error`, as SQLite reports it while the statement runs.
The catalog keeps each `REFERENCES` clause and `FOREIGN KEY` constraint with its `ON DELETE`
and `ON UPDATE` actions, as `PRAGMA foreign_key_list` reports it, and whether it is
`DEFERRABLE INITIALLY DEFERRED`. With foreign keys off, SQLite's default, a foreign key has no
effect on writes apart from its prepare errors; enforced foreign keys are described below. A
record without an execution profile and with a foreign key is out of scope, as its setup may
have turned foreign keys on. A CREATE TABLE with constraints and defaults runs in the
migration as in the schema.

Foreign keys (ADR 0018, D4) are on when the execution profile turns them on.
`PRAGMA foreign_keys = value` (`on`, `off`, `yes`, `no`, `true`, `false`, `0` or `1`) changes
the setting outside a transaction and does nothing inside one, and `PRAGMA foreign_keys` is one
row with the column `foreign_keys`, 1 or 0. With foreign keys on, `INSERT`, `UPDATE`, `DELETE`,
the rows that `REPLACE` deletes and the implicit `DELETE` that `DROP TABLE` runs for a table
that foreign keys reference count violations as SQLite's `sqlite3FkCheck` does, row by row in
rowid order (primary-key order for a `WITHOUT ROWID` table), and a statement that ends with a
count other than zero is `FOREIGN KEY constraint failed` and changes nothing. A child key
looks up its parent under the parent index's affinity and collation, a parent row finds its
child rows as `parent = child` compares them, and a child key with a NULL column needs no
parent. The actions `CASCADE`, `SET NULL`, `SET DEFAULT`, `RESTRICT` and `NO ACTION` run after
each deleted row and after each updated row whose parent key changes, also in chains and for a
table that references itself, with every constraint of their rows ABORT. A write that
processes a foreign key whose parent key is no primary key or `UNIQUE` index is
`foreign key mismatch`, and one whose parent table does not exist is `no such table`, except in
the implicit `DELETE` of `DROP TABLE`. A deferred foreign key is the restriction
`deferred-foreign-key`, `ON CONFLICT DO UPDATE` on a table with a key to check is
`foreign-key-upsert`, and a write whose actions nest deeper than the trigger depth limit, or
whose `REPLACE` deletes more than one row with foreign keys, is not described.

A generated column (ADR 0014, slice 5) is `VIRTUAL` or `STORED`, and `PRAGMA table_xinfo`
reports it with `hidden` 2 or 3. Its expression resolves over the table's columns after the
CHECK constraints, without the rowid; every write computes the generated values of the
row, in an order that respects their dependencies, stores them with the column's affinity,
and then checks NOT NULL, CHECK and the unique keys. An INSERT without a column list takes
one value for each column that is not generated. SQLite's prepare errors apply: a generated
column in the primary key, a DEFAULT on it, a second `AS` on one column, `rowid` or a
qualified name in its expression, a time keyword, a table whose columns are all generated,
and an INSERT or UPDATE that names a generated column. A loop of generated columns (`generated-loop`), a date and time function or a JSON
function in the expression (`generated-function`), a `DO UPDATE` of a generated column
(`upsert-generated`) and ADD COLUMN of a generated column (`add-column-generated`) are
model restrictions.

A `STRICT` table (ADR 0014, slice 6) admits only the declared types `INT`, `INTEGER`,
`REAL`, `TEXT`, `BLOB` and `ANY`, with ASCII case ignored; another type and a column
without a type are SQLite's prepare errors. After the column's affinity applies, a value
whose storage class does not fit the type fails the statement with SQLite's constraint
error, for example `cannot store TEXT value in INTEGER column s.i`: `INT` and `INTEGER`
take integers, `REAL` integers and reals, `TEXT` text, `BLOB` blobs, and NULL fits every
type. `ANY` takes every value as written, with no affinity, also in a DEFAULT. Each
primary-key column other than the rowid alias is NOT NULL, with ABORT unless it declares
its own NOT NULL, as in SQLite. The type
check comes after NOT NULL and before CHECK and the unique keys, covers UPDATE, `DO
UPDATE` and generated columns, and acts as ABORT under every conflict algorithm. ADD
COLUMN to a `STRICT` table with a type that it does not admit, or with a default that does
not fit the type, is a model restriction (`add-column-strict-type`), because SQLite reports
it only while the statement runs.

`DROP TABLE` (ADR 0014, slice 7) removes the table, its rows and its indexes, and `DROP
INDEX` removes one index; the later catalog objects move to lower positions, and later
statements resolve against the catalog without the dropped objects. A ROLLBACK brings a
dropped object back with its rows. SQLite's prepare errors apply, with names compared with
ASCII case ignored: `no such table` and `no such index`, also for an object of the other
kind, which `IF EXISTS` turns into a statement that does nothing, and `table sqlite_master
may not be dropped` for SQLite's schema tables under any of their names, also with `IF
EXISTS`. The catalog does not name the indexes of UNIQUE and PRIMARY KEY constraints, so a
DROP INDEX of another name that begins with `sqlite_autoindex_` is a model restriction
(`drop-constraint-index`). With foreign keys on, `DROP TABLE` first deletes the rows of a table
that foreign keys reference, with their actions, and fails when a violation remains. The model
has no views.

`CREATE TRIGGER [IF NOT EXISTS] name [BEFORE|AFTER] INSERT|UPDATE [OF columns]|DELETE ON table
[FOR EACH ROW] [WHEN condition] BEGIN statements END` (ADR 0018, D5) has a body of `INSERT ...
VALUES`, `UPDATE`, `DELETE` and `SELECT` statements, and `DROP TRIGGER [IF EXISTS] name`
removes one trigger. Trigger names have a namespace of their own, and `DROP TABLE` drops the
triggers of its table. SQLite's prepare errors apply: `no such table`, `trigger ... already
exists`, which `IF NOT EXISTS` turns into a statement that does nothing, `cannot create
trigger on system table`, `no such trigger`, which `IF EXISTS` turns into a statement that does
nothing, and `RAISE() may only be used within a trigger-program` for `RAISE` outside a
trigger. A write resolves the program of every trigger that it may fire, also through the
statements of those programs and the foreign-key actions, as SQLite prepares them with the
write: a name that a body or a `WHEN` condition cannot resolve, such as `OLD` in an `INSERT`
trigger or a missing table, is a prepare error of the write. `NEW` and `OLD` are seen only as
qualified names; a source of the same name in the query wins for its columns. A reference to
them has the collation of its column and, as in SQLite, no affinity: in a trigger on
`t(a INTEGER)`, `new.a = '1'` is 0 for the value 1. `RAISE` in a
trigger is modeled as the one result column of a `SELECT` without `FROM`, alone or as a result
of its `CASE` (`raise-form` elsewhere); `ON CONFLICT DO UPDATE` in a body, a function that can fail in a write of a body that no
earlier rule restricts (in the `VALUES` of an `INSERT` it is `constant-function-error`, as in a
statement), and a `WHEN` with a subquery or a function that can fail are `trigger-form`; a `BEFORE UPDATE` or `BEFORE DELETE`
trigger that writes its own table is `trigger-writes-own-table`; and two triggers of one table,
time and event in the starting schema are `schema-trigger-order`.

A write with triggers runs row by row, as with foreign keys on, in rowid order (primary-key order
for a `WITHOUT ROWID` table). For each row, the `BEFORE` triggers run after the rowid alias
check (`datatype mismatch`) and, when the table has a `BEFORE` trigger of the event, the types
of a `STRICT` table, and before NOT NULL, CHECK and the unique keys; the `AFTER` triggers run
after the row is written and after its foreign-key actions. Of the triggers of one time and
event, the one created last runs first. `WHEN` is evaluated for each row, and NULL and false
skip the trigger. In a `BEFORE INSERT` trigger, `NEW` of a rowid alias is -1 when the row gives
NULL. A body statement runs with the conflict algorithm of the statement that fired it when
that has one, else with its own; the writes of foreign-key actions pass on ABORT.
`RAISE(IGNORE)` ends the row: the rest of its trigger, the triggers after it, and in a `BEFORE`
trigger the row's own write. `RAISE(ABORT, ...)`, `RAISE(FAIL, ...)` and `RAISE(ROLLBACK, ...)`
fail the statement as a constraint failure with that algorithm. With recursive triggers off,
SQLite's default and the only setting that the model describes, a trigger does not run while it
already runs. The rows that `REPLACE` deletes and the implicit `DELETE` of `DROP TABLE` fire no
`DELETE` trigger; the writes of foreign-key actions fire the triggers of the child table. The
change count of a statement counts its own rows only. A write nested deeper than the trigger
depth limit, an `UPDATE` of a body that fails a constraint under an inherited algorithm other
than ABORT, and a write whose statement or body statement has subqueries while a trigger or an
action changes a table are not described. In a trigger, a qualified table
name, `INDEXED BY`, `UPDATE OR`, `UPDATE FROM`, `INSERT ... SELECT`, `RETURNING` and a subquery
in `WHEN` are refused.

A collation (ADR 0014, slice 3) is `BINARY`, `NOCASE` or `RTRIM`, with ASCII case of the
name ignored. `NOCASE` compares TEXT with the ASCII capitals folded, and `RTRIM` compares
TEXT without trailing spaces; neither changes a value of another storage class. A column
has the collation of its `COLLATE` clause, else `BINARY`; an index term has that of an
explicit `COLLATE`, else that of its column. A primary key, a `UNIQUE` column and a unique
index compare their terms under these collations, and a `WITHOUT ROWID` table scans in
that order. Resolution decides each collation by SQLite's rules: a comparison uses an
explicit `COLLATE` of its left operand, else of its right operand, else the collation of
a column on the left, else on the right, else `BINARY`; `COLLATE` passes through unary plus
and `CAST`. An `ORDER BY` or `GROUP BY` term, `min` and `max` use the collation of their
expression, and the equality of `USING` and `NATURAL` that of its left column. A
`GROUP BY` term may be a column name under one `COLLATE`. An unknown name in a column
definition or an index term is SQLite's prepare error `no such collation sequence: %s`;
in any other expression it is the restriction `unknown-collation`, because SQLite looks
the name up only where it uses the collation, and its query planner decides some of
those uses. `COLLATE` in an `ON CONFLICT` target or in a key of a table constraint is
refused.

ADD COLUMN supports literal defaults, with optional NOT NULL and COLLATE. Existing rows
read the default under the column affinity. Without a default they read NULL.
NOT NULL with NULL succeeds on an empty table and fails during execution on a
populated table, retaining the prior catalog and rows. A time keyword default
succeeds on an empty table and fails during execution on a populated table with
SQLite's `Cannot add a column with non-constant default` (slice 6e2). Other
nonconstant defaults remain unsupported. Old-row readback can differ from INSERT default
evaluation: TEXT DEFAULT 1.50 reads as 1.50 for old rows.

## Resolution

Lean's `resolve` follows SQLite's name resolution: ASCII-only case folding, one
namespace for tables and indexes, SQLite's affinity rules on the declared type
text, column positions, defaults of omitted INSERT columns, and SQLite's
numeric-literal conversion. Limits come from the execution profile. A statement
that SQLite refuses to prepare becomes its prepare error at its position, for
example `no such table`, `table already exists`, `duplicate column name` or
`too many columns`. The script stops there under autocommit and keeps the
successful prefix. Predicting an error alone never establishes `VIOLATED`.

SQL that SQLite accepts but the model does not describe is a model restriction:
the whole request is `UNSUPPORTED` at the byte range of the refused node. In the
migration these are, among others: `ADD COLUMN` with an unmodeled default expression; rowid column
names; time values; a `SET` value that reads the row for a column of a unique key; a
column named twice. In a `SELECT`: an aggregate inside an expression; a result column
outside `GROUP BY` in an aggregate query; `ORDER BY` terms of an aggregate query
other than result column numbers and aliases; a result column alias in `WHERE`
or inside an `ORDER BY` expression; a query of SQLite's own tables, such as
`sqlite_schema`; other join operators, such as `OUTER LEFT JOIN`; two sources with
the same name; an `ON` condition that names a
table joined after it; `SUM` in a query with `GROUP BY` and `LIMIT` or `OFFSET`; and
`LIMIT` or `OFFSET` other than
an integer literal or a lone parameter, or a negative literal `OFFSET`. Each restriction message says what to
change.

### Restriction registry

Each model restriction has a stable id. A rejection reports it in the field
`restriction`, next to its message, and the conformance predictions record it too.
The registry is `RestrictionKind` in
`packages/belay-sqlite-model/Belay/Sqlite/Model/Resolution/Restrictions.lean`, with the ids and
messages in `RestrictionText.lean`. Every id has one row in this table;
`tests/restriction_registry_test.py` checks that the table and the registry list the
same ids. `conformance/restriction_examples.py` has, for every id, a schema and a
migration that the resolver refuses with that id, and a test runs each one. Syntax
that the frontend refuses before resolution, such as `DISTINCT` or
`UPDATE OR IGNORE`, has no id. `just restriction-costs` counts, for each id and for each kind
of frontend refusal, the cases of the claimed corpora that it keeps out of scope.

The registry has three parts (ADR 0013, D4), which `RestrictionKind.registry` in
`RestrictionRegistry.lean` gives for each id. *Unsupported* SQL is not yet modeled.
*Undecided* SQL has a result that depends on an internal order of SQLite, which the model
does not predict. *Unrepresented* SQL is SQL that the resolved form cannot express,
although evaluation could decide it: these are the model's own limitations, and the part
should shrink.

#### Unsupported

| Id | Restriction | Introduced by |
| --- | --- | --- |
| `schema-statement` | A schema contains only CREATE TABLE, CREATE INDEX and CREATE TRIGGER statements | ADR 0008, ADR 0018 |
| `engine-table` | Engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled | ADR 0008 |
| `rowid-column-name` | Column names `rowid`, `_rowid_` and `oid` are not modeled | ADR 0008 |
| `unmodeled-default` | Only literal defaults and the time keywords are modeled | ADR 0008 |
| `index-string-term` | A string literal as a key term of CREATE INDEX, also a double-quoted name that is no column, is not modeled | ADR 0014, slice 1 |
| `index-date-function` | A date and time function in a key term or the filter of CREATE INDEX is not modeled | ADR 0014, slice 1 |
| `index-json-function` | A JSON function in a key term or the filter of CREATE INDEX is not modeled | ADR 0014, slice 1 |
| `check-function` | A time keyword, a date and time function or a JSON function in a CHECK constraint is not modeled | ADR 0014, slice 4 |
| `add-column-check-error` | A CHECK of ADD COLUMN that SQLite cannot resolve is not modeled, because SQLite reports it while the statement runs | ADR 0014, slice 4 |
| `generated-function` | A date and time function or a JSON function in a generated column is not modeled | ADR 0014, slice 5 |
| `generated-loop` | Generated columns that read each other in a loop are not modeled, because SQLite reports the loop while CREATE TABLE runs | ADR 0014, slice 5 |
| `parameter-error-order` | A parameter in a CHECK constraint, a generated column or an index, in an expression where SQLite can also find another error or removes the parameter before it resolves names (`? AND 0`, `? IN ()`), is not modeled | ADR 0019, D1 |
| `add-column-generated` | ADD COLUMN of a generated column is not modeled | ADR 0014, slice 5 |
| `drop-constraint-index` | DROP INDEX of a name that begins with `sqlite_autoindex_` and is no catalog index is not modeled, because the catalog does not name the indexes of UNIQUE and PRIMARY KEY constraints, which SQLite does not drop | ADR 0014, slice 7 |
| `add-column-strict-type` | ADD COLUMN to a `STRICT` table with a type that it does not admit, or with a default that does not fit the type, is not modeled, because SQLite reports it while the statement runs | ADR 0014, slice 6 |
| `add-column-constraint` | The added column requires unmodeled default evaluation | ADR 0008 |
| `constraint-algorithm-update` | UPDATE of a table with ON CONFLICT constraint algorithms is not modeled | ADR 0012 amendment 4, slice 5d |
| `replace-default` | REPLACE of a NOT NULL column with a default is not modeled | ADR 0012 amendment 4, slice 5d |
| `insert-column-twice` | A column named twice in INSERT is not modeled | ADR 0008 |
| `update-column-twice` | A column assigned twice in UPDATE is not modeled | ADR 0008 |
| `join-operator` | A join operator that SQLite refuses with `unknown join type`, such as `INNER OUTER JOIN`, is not modeled | ADR 0012 amendment 2; ADR 0013 amendment 2 |
| `system-table` | Queries of SQLite's own tables, such as `sqlite_schema`, are not modeled | ADR 0012 slice 1 |
| `unmodeled-function` | A function of the pinned library that the model does not describe, or a form of it that the model does not describe, such as a window function or `sqlite_version()` | ADR 0012 slices 1, 2, 6b and 6c; ADR 0015 |
| `aggregate-in-expression` | An aggregate where the model does not describe it, such as the argument of a function that can fail, is not modeled | ADR 0012 slice 1; ADR 0018, slice 3 |
| `alias-in-expression` | A result column alias inside WHERE or an ORDER BY expression is not modeled | ADR 0012 slice 1 |
| `group-by-term` | Only a column name, also under COLLATE, or a result column number is modeled in GROUP BY | ADR 0012 slice 1; ADR 0014, slice 3 |
| `bare-column` | A result column outside GROUP BY in an aggregate query is not modeled | ADR 0012 slice 1 |
| `aggregate-order-by` | An `ORDER BY` term of an aggregate query that reads a column outside `GROUP BY` is not modeled | ADR 0012 slice 1; ADR 0018, slice 3 |
| `window-value` | Only an integer literal or a lone parameter is modeled as LIMIT or OFFSET | ADR 0012 slice 1; ADR 0019 |
| `negative-offset` | A negative literal OFFSET is not modeled; a negative bound OFFSET skips no rows | ADR 0012 slice 1; ADR 0019 |
| `table-function` | Only `json_each` with one or two arguments is modeled as a table-valued function in FROM | ADR 0012 slice 6d |
| `later-table-in-on` | An ON condition that names a source joined after it is not modeled: SQLite moves it to WHERE without outer joins and refuses it otherwise | ADR 0012 amendment 2; ADR 0013 amendment 2 |
| `function-join` | `json_each` as the right operand of RIGHT or FULL JOIN, with NATURAL or USING, or before a NATURAL JOIN, is not modeled | ADR 0012 slice 6d; ADR 0013 amendment 2 |
| `later-source-in-arguments` | An argument of `json_each` that reads a later source is not modeled, because the model joins in written order | ADR 0012 slice 6d; ADR 0013 amendment 2 |
| `json-subtype` | A JSON call passed on through `coalesce`, `iif`, `nullif`, `min` or `max` as a value argument of `json_quote`, `json_array`, `json_object`, an edit function or a JSON aggregate is not modeled, because SQLite keeps the JSON subtype through such expressions | ADR 0015, slice 3 |
| `subquery-here` | A subquery outside the expressions of a `SELECT` that the model resolves, such as in an `ON` condition, a `json_each` argument or another statement, is not modeled | ADR 0018, slice 1 |
| `outer-aggregate` | An aggregate in a subquery whose argument reads a column of a query around it is not modeled, because SQLite computes an aggregate whose argument reads only outer columns in the outer query | ADR 0018, slice 1 |
| `deferred-foreign-key` | With foreign keys on, a write that checks a `DEFERRABLE INITIALLY DEFERRED` foreign key is not modeled, because SQLite counts its violations until `COMMIT` | ADR 0018, slice 4 |
| `foreign-key-upsert` | With foreign keys on, `INSERT` with `ON CONFLICT DO UPDATE` on a table with a foreign key to check is not modeled | ADR 0018, slice 4 |
| `raise-form` | `RAISE` in a trigger outside the one result column of a `SELECT` without `FROM`, alone or as a result of its `CASE`, or with a message that can fail, is not modeled | ADR 0018, slice 5 |
| `trigger-form` | A trigger with `ON CONFLICT DO UPDATE` in its body, with a function that can fail in a write of its body that no other restriction covers, with a `WHEN` condition that has a function that can fail or a subquery, or with too many triggers that fire each other, and `ON CONFLICT DO UPDATE` on a table with a trigger, are not modeled | ADR 0018, slice 5 |
| `compound-subquery-column` | `x IN (q)` and a scalar subquery `(q)` over a compound `SELECT` with an operator other than `UNION ALL` and an `ORDER BY` term with `COLLATE` are not modeled, because SQLite then reads the column of a derived table | ADR 0019, D3 |
| `compound-order-by-term` | An `ORDER BY` term of a compound `SELECT` that the model cannot match with a result column as SQLite does, such as an aggregate, or a `COLLATE` term after which SQLite names a result column at random, is not modeled | ADR 0019, D3 |

#### Undecided

| Id | Restriction | Introduced by |
| --- | --- | --- |
| `row-dependent-key` | A SET value that reads the row is not modeled for a column of a unique key | ADR 0012 amendment 1 (question 1) |
| `conflict-without-target` | DO UPDATE without a conflict target is not modeled for a table with more than one key | ADR 0012 amendment 4 (owner decision 2) |
| `mixed-conflict-algorithms` | Keys of one INSERT with different conflict algorithms other than REPLACE are not modeled | ADR 0012 amendment 4, slice 5d |
| `windowed-group-sum` | SUM in a grouped query with LIMIT or OFFSET is not modeled, because SQLite may stop before an overflowing group | ADR 0012 slice 2 |
| `constant-function-error` | A constant value in VALUES or SET whose JSON function fails is not modeled, because the model does not describe when SQLite evaluates it | ADR 0012 slice 6b |
| `unknown-collation` | COLLATE with a name other than BINARY, NOCASE or RTRIM in an expression is not modeled, because SQLite looks the name up only where its query planner uses the collation | ADR 0014, slice 3 |
| `upsert-generated` | DO UPDATE of a generated column is not modeled, because SQLite refuses it only when a row conflicts | ADR 0014, slice 5 |
| `subquery-fallible-call` | A query without `FROM` that has a subquery and a call that can fail is not modeled, because a value of the subquery that SQLite's plan chooses could avoid the failure | ADR 0018, slice 1 |
| `subquery-reads-target` | A subquery of `INSERT`, `UPDATE` or `DELETE` that reads the written table is not modeled, because SQLite evaluates a correlated one over the rows that the statement has already changed | ADR 0018, slice 1 |
| `distinct-order-by` | An `ORDER BY` expression of `SELECT DISTINCT` that is no result column is not modeled, because SQLite sorts each kept row by the value of a row that its plan chooses | ADR 0018, slice 3 |
| `trigger-writes-own-table` | A `BEFORE UPDATE` or `BEFORE DELETE` trigger that writes its own table, also through the triggers and actions that it fires, is not modeled, because SQLite documents the result as undefined | ADR 0018, slice 5 |
| `schema-trigger-order` | Two triggers of one table, time and event in the starting schema are not modeled, because the schema does not say which one runs first | ADR 0018, slice 5 |

#### Unrepresented

| Id | Restriction | Introduced by |
| --- | --- | --- |
| `rowid-name` | A rowid name that is not a column is not modeled in an expression over a table, or as the SET column of a table without an `INTEGER PRIMARY KEY`; in VALUES it resolves as any other name, and as the SET column of a table with an `INTEGER PRIMARY KEY` it assigns that column | ADR 0012 slice 3a; extended 2026-10-14 and 2026-10-21 |

## Execution

The execution semantics runs the resolved statements on a database keyed by
catalog position. Transactions and data changes are supplied as SQL, not implied
by a profile. INSERT appends its rows with ordinary automatic rowid allocation;
UPDATE sets its assignments in each row that its filter selects. A `SELECT`
changes nothing; its result rows follow ADR 0012: rows in rowid order, the
`WHERE` filter with three-valued logic, groups, result columns, a stable sort by
the `ORDER BY` terms with SQLite's comparison of values, then the window. As SQLite
promises the order of `ORDER BY` only, the model also gives every result that SQLite may give
(ADR 0018, D6): each result has the rows of each tie group of the `ORDER BY` terms (all rows
without `ORDER BY`) in normal form, sorted by SQLite's comparison with an integer before a real of
the same value, and a group that `LIMIT` or `OFFSET` cuts gives each choice of as many of its
rows as the window takes. The one result above, with its groups in normal form, is in the list,
and the conformance runner checks that SQLite's rows are too.
Arithmetic, `CAST` and the conversions between text and numbers follow the pinned
SQLite source step by step: integer arithmetic while the result fits in 64 bits,
else double arithmetic; NULL for a division by zero or a NaN result; SQLite's own
text-to-REAL conversion and its 15-digit text of a REAL, which are not correctly
rounded; and `SUM` and `AVG` with SQLite's summation. A `SUM` that overflows the
64-bit integers stops the query with `integer overflow`, unless a later REAL input
makes the sum approximate. JSON functions read JSON and JSON5 text as SQLite 3.51.0
does, and give SQLite's values and rendered JSON text (slice 6b). A JSON function that
fails with `malformed JSON`, `bad JSON path`, the `json_valid` flags error, an argument error
of `json_object` or an edit function, or `JSON cannot hold BLOB values` stops a query without `FROM` where SQLite
certainly evaluates it. Every other statement in which a JSON function may fail is
outside the supported subset for that data, because SQLite skips or folds some
expressions and evaluates a constant `WHERE` term before it reads the rows: a query with
`FROM`, a write, a failure under `AND`, `OR` or `COALESCE`, and JSONB that the model does not
read. Each statement sees one clock value, SQLite's
Julian-day milliseconds from the VFS method `xCurrentTimeInt64`, and different statements
may see different values (slice 6e2). `CURRENT_TIME`, `CURRENT_DATE` and
`CURRENT_TIMESTAMP` give it as SQLite's text `HH:MM:SS`, `YYYY-MM-DD` and
`YYYY-MM-DD HH:MM:SS`, with the seconds truncated; a clock value of zero or less gives
NULL, and a value after the year 9999 gives SQLite's zero date. The date and time
functions read the time value `now`, written or read from a column, as the statement's
clock value, and give SQLite's value for every other time value, NULL for one that SQLite
cannot read (slice 6f). They apply their modifiers from left to right as SQLite does;
`localtime` and `utc` use UTC, the time zone of every execution profile (slice 6g). The clock values are inputs of the
execution: the model fixes no clock. Literal writes
have checked data-domain obligations: existing key cells and filter cells must
be integers or NULL, existing constraints must hold, and the random-search branch
at the maximum rowid is outside the admitted domain. New NOT NULL and uniqueness
violations are modeled statement failures; unsupported coercions or comparison
classes are not invented SQLite error outcomes.

An error inside a transaction does not imply rollback. The model distinguishes
the connection-visible state from its committed snapshot when a transaction
remains open. The model does not report a final uncommitted transaction as
committed. Resource, concurrency and crash failures remain outside
the fixed execution assumptions. See [execution profiles](execution-profile.md).
