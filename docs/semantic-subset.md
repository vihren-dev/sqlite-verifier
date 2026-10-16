# Supported subset

The verifier handles SQL in three layers (ADR 0008). The frontend maps the pinned
SQLite syntax tree to statement syntax. Lean resolves the syntax against the
catalog. The execution semantics runs the resolved statements. Each layer has a
boundary of its own.

## Statement syntax

The frontend maps these statements, and refuses every other statement as
`UNSUPPORTED` at its byte range:

- `CREATE TABLE` with column definitions (name, declared type text, `NOT NULL`,
  `PRIMARY KEY` with its sort order, `UNIQUE`, and `DEFAULT` with a literal, a
  signed number, a time keyword or a name) and table `PRIMARY KEY` and `UNIQUE`
  constraints over plain column names;
- `CREATE [UNIQUE] INDEX` over plain column names;
- `ALTER TABLE … ADD [COLUMN]` with one column definition;
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
  with an optional alias (ADR 0012, slice 1). `FROM` is one table, or tables joined
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

Expressions are `NULL`, numeric, string and blob literals, the time keywords,
names, unary `-` and `+`, and `=`. Inside a `SELECT`, they may also be the other
comparisons, `IS` and `IS NOT`, `AND`, `OR`, `NOT`, `IS NULL` and its forms,
parentheses, `COUNT(*)`, `COUNT`, `MIN`, `MAX`, `SUM` and `AVG` of one argument, the arithmetic
operators `+`, `-`, `*`, `/` and `%`, unary `-` and `+` of any expression,
`CAST(expression AS type)`, and `COALESCE` of two or more arguments (ADR 0012,
slice 2). In a write, a `VALUES` item may be any of these expressions that names no
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
REPLACE of a NOT NULL column with a default is `replace-default`. Named
constraints, collations, `CHECK`, `REFERENCES`, generated columns, `UPDATE OR`, a target with a direction, collation,
`NULLS` order, qualified name or `WHERE`, `WITH`, `FROM` in writes, sort modifiers in keys,
partial and expression indexes, `IF NOT EXISTS`, `TEMP`, schema names, table
options, `AS SELECT`, views, triggers, virtual tables, `EXPLAIN`, `PRAGMA`,
compound `SELECT`, `DISTINCT`, `HAVING`, subqueries and table-valued functions in
`FROM`, schema-qualified tables and columns, `NULLS FIRST` and `NULLS LAST`, and
other functions are refused. Names keep
their case as written; quotes are removed as SQLite removes them. Numeric literals
and declared types keep their text.

Every command retains its original half-open UTF-8 byte span; semicolons in names
and trigger bodies cannot split commands. The CLI requires at least one migration
statement. An empty starting schema is allowed.

## Schema description

`schema.sql` describes the starting catalog. It may contain only `CREATE TABLE`
and `CREATE INDEX`, in an order that SQLite can run: an index follows its table.
A schema statement that SQLite refuses to prepare, for example a second table
with the same name, is `INPUT_ERROR` with SQLite's message. The description may
contain keys, `NOT NULL`, the `CURRENT_TIMESTAMP` default, indexes and the exact
native `sqlite_stat1` and `sqlite_stat4` tables, and `INTEGER PRIMARY KEY` rowid
aliases (slice 5b): the column is the rowid; INSERT of NULL or no value gives the next
rowid, another value must be an integer after INTEGER affinity, else SQLite's
`datatype mismatch`, and UPDATE of the alias moves the row. Other defaults and other
reserved names are model restrictions.

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
migration these are, among others: `CREATE INDEX`; `CREATE TABLE` with
constraints or defaults; `ADD COLUMN` with a constraint or default; rowid column
names; time values; a `SET` value that reads the row for a column of a unique key; a
column named twice. In a `SELECT`: a comparison whose affinity rule would convert a value; a
column, literal, `COALESCE`, or `CAST` to TEXT or BLOB used as a condition; an aggregate inside an expression; a result column
outside `GROUP BY` in an aggregate query; `ORDER BY` terms of an aggregate query
other than result column numbers and aliases; a result column alias in `WHERE`
or inside an `ORDER BY` expression; a query of SQLite's own tables, such as
`sqlite_schema`; other join operators, such as `OUTER LEFT JOIN`; two sources with
the same name; an `ON` condition that names a
table joined after it; `SUM` in a query with `GROUP BY` and `LIMIT` or `OFFSET`; and
`LIMIT` or `OFFSET` other than
an integer literal, or a negative `OFFSET`. Each restriction message says what to
change.

### Restriction registry

Each model restriction has a stable id. A rejection reports it in the field
`restriction`, next to its message, and the conformance predictions record it too.
The registry is `RestrictionKind` in
`packages/belay-sqlite/Belay/Sqlite/Resolution/Restrictions.lean`, with the ids and
messages in `RestrictionText.lean`. Every id has one row in this table;
`tests/restriction_registry_test.py` checks that the table and the registry list the
same ids. `conformance/restriction_examples.py` has, for every id, a schema and a
migration that the resolver refuses with that id, and a test runs each one. Syntax
that the frontend refuses before resolution, such as `DISTINCT` or
`UPDATE OR IGNORE`, has no id. `just restriction-costs` counts, for each id and for each kind
of frontend refusal, the cases of the claimed corpora that it keeps out of scope.

| Id | Restriction | Introduced by |
| --- | --- | --- |
| `schema-statement` | A schema contains only CREATE TABLE and CREATE INDEX statements | ADR 0008 |
| `engine-table` | Engine-managed tables other than sqlite_stat1 and sqlite_stat4 are not modeled | ADR 0008 |
| `rowid-column-name` | Column names `rowid`, `_rowid_` and `oid` are not modeled | ADR 0008 |
| `create-table-constraints` | Constraints and defaults in a CREATE TABLE that runs are not modeled | ADR 0008 |
| `unmodeled-default` | Only the `CURRENT_TIMESTAMP` default is modeled | ADR 0008 |
| `create-index-runs` | A CREATE INDEX that runs is not modeled | ADR 0008 |
| `add-column-constraint` | Only a nullable column without a default can be added | ADR 0008 |
| `time-value` | Time values are not modeled | ADR 0008 |
| `row-dependent-key` | A SET value that reads the row is not modeled for a column of a unique key | ADR 0012 amendment 1 (question 1) |
| `conflict-without-target` | DO UPDATE without a conflict target is not modeled for a table with more than one key | ADR 0012 amendment 4 (owner decision 2) |
| `mixed-conflict-algorithms` | Keys of one INSERT with different conflict algorithms other than REPLACE are not modeled | ADR 0012 amendment 4, slice 5d |
| `constraint-algorithm-update` | UPDATE of a table with ON CONFLICT constraint algorithms is not modeled | ADR 0012 amendment 4, slice 5d |
| `replace-default` | REPLACE of a NOT NULL column with a default is not modeled | ADR 0012 amendment 4, slice 5d |
| `insert-column-twice` | A column named twice in INSERT is not modeled | ADR 0008 |
| `update-column-twice` | A column assigned twice in UPDATE is not modeled | ADR 0008 |
| `rowid-name` | A rowid name that is not a column is not modeled in an expression over a table; in VALUES it resolves as any other name | ADR 0012 slice 3a; extended 2026-10-14 |
| `join-operator` | A join operator with other keywords, or in another order, such as `OUTER LEFT JOIN`, is not modeled | ADR 0012 amendment 2 |
| `duplicate-source` | Two sources of a query with the same name are not modeled | ADR 0012 amendment 2 (question 3) |
| `later-table-in-on` | An ON condition that names a table joined after it is not modeled | ADR 0012 amendment 2 |
| `system-table` | Queries of SQLite's own tables, such as `sqlite_schema`, are not modeled | ADR 0012 slice 1 |
| `unmodeled-function` | Only `COUNT(*)`, `COUNT`, `MIN`, `MAX`, `SUM` and `AVG` of one argument, and `COALESCE` of two or more arguments are modeled as functions | ADR 0012 slices 1 and 2 |
| `aggregate-in-expression` | An aggregate inside an expression is not modeled | ADR 0012 slice 1 |
| `alias-in-expression` | A result column alias inside WHERE or an ORDER BY expression is not modeled | ADR 0012 slice 1 |
| `value-as-condition` | A value used as a condition is not modeled | ADR 0012 slice 1 |
| `mixed-affinity-comparison` | A comparison of columns with different kinds of affinity is not modeled | ADR 0012 slice 1 |
| `text-to-number` | A text value compared with a numeric column would be converted to a number | ADR 0012 slice 1 |
| `number-to-text` | A number compared with a TEXT column would be converted to text | ADR 0012 slice 1 |
| `group-by-term` | Only a column name or a result column number is modeled in GROUP BY | ADR 0012 slice 1 |
| `bare-column` | A result column outside GROUP BY in an aggregate query is not modeled | ADR 0012 slice 1 |
| `aggregate-order-by` | An aggregate query is modeled with ORDER BY result column numbers or aliases only | ADR 0012 slice 1 |
| `window-value` | Only an integer literal is modeled as LIMIT or OFFSET | ADR 0012 slice 1 |
| `negative-offset` | A negative OFFSET is not modeled | ADR 0012 slice 1 |
| `windowed-group-sum` | SUM in a grouped query with LIMIT or OFFSET is not modeled, because SQLite may stop before an overflowing group | ADR 0012 slice 2 |

## Execution

The execution semantics runs the resolved statements on a database keyed by
catalog position. Transactions and data changes are supplied as SQL, not implied
by a profile. INSERT appends its rows with ordinary automatic rowid allocation;
UPDATE sets its assignments in each row that its filter selects. A `SELECT`
changes nothing; its result rows follow ADR 0012: rows in rowid order, the
`WHERE` filter with three-valued logic, groups, result columns, a stable sort by
the `ORDER BY` terms with SQLite's comparison of values, then the window.
Arithmetic, `CAST` and the conversions between text and numbers follow the pinned
SQLite source step by step: integer arithmetic while the result fits in 64 bits,
else double arithmetic; NULL for a division by zero or a NaN result; SQLite's own
text-to-REAL conversion and its 15-digit text of a REAL, which are not correctly
rounded; and `SUM` and `AVG` with SQLite's summation. A `SUM` that overflows the
64-bit integers stops the query with `integer overflow`, unless a later REAL input
makes the sum approximate. Literal writes
have checked data-domain obligations: existing key cells and filter cells must
be integers or NULL, existing constraints must hold, and the random-search branch
at the maximum rowid is outside the admitted domain. New NOT NULL and uniqueness
violations are modeled statement failures; unsupported coercions or comparison
classes are not invented SQLite error outcomes.

An error inside a transaction does not imply rollback. The model distinguishes
the connection-visible state from its committed snapshot when a transaction
remains open. A final uncommitted transaction cannot be reported as a committed
successful migration. Resource, concurrency and crash failures remain outside
the fixed execution assumptions. See [execution profiles](execution-profile.md)
and [profile input](profile-inputs.md).

`SqlInputs.lean` contains only literal statement syntax, resolved statements and
the resulting catalog. The driver seals it separately from candidate definitions,
and the gates resolve the record again to check it. A resolution result is not
proof acceptance or evidence of native execution.

The [Atuin example](../examples/atuin/README.md) supplies only the upstream
nullable shell-column ALTER payload and proves recovery of the approved old
histories. It does not use transaction or literal DML wrappers; SQLx catalog
maintenance and invocation remain trusted and outside the verified payload.
