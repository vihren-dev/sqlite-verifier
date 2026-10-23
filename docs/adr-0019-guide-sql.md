# ADR 0019: Parameters, pragmas, compound queries and the table rebuild

Date: 2026-10-20. Status: ACCEPTED on 2026-10-22 (owner decisions below).
Implementation: slice by slice, in the order of D7, each with its own task file, as local
commits; each slice gets its pull requests at its end (owner decision 3), because the slices
of [ADR 0017](adr-0017-user-surface.md) that need them come between them.
Audience: designers and reviewers.
Related: [ADR 0018](adr-0018-surface-sql.md) (the SQL that the user surface needs; its
"Not decided here" lists most of this work), [ADR 0017](adr-0017-user-surface.md) (the user
surface), [ADR 0012](adr-0012-query-semantics.md) (queries), [ADR 0014](adr-0014-schema-features.md)
(schema features), [ADR 0011](adr-0011-product-trust-and-development-integrity.md) (the judge),
[ADR 0022](adr-0022-database-validity.md) (the facts of a valid database, which D2 reads).

## Overview

ADR 0018 adds the SQL that ADR 0017's D5 names. The target user guide uses more SQL than
that list: its lead example, the table rebuild that cascades, copies a table with
`INSERT ... SELECT`, renames it with `ALTER TABLE ... RENAME TO` and checks it with
`PRAGMA foreign_key_check`; its schema facts read `pragma_table_info`; its claims compare
tables with `EXCEPT`; and its programs bind parameters such as `:e`. The out-of-scope cases
of the corpora point to the same work and to a few more forms. This ADR adds them to the
model, in six slices, with the rules of ADRs 0012 to 0018: each slice follows SQLite 3.51.0
exactly and is checked against native SQLite.

## Context

Measured on 2026-10-20 with `experiments/model-gaps/next_groups.py`, over the local verdict
after slice 1 of ADR 0018. The measurement counts every group of ADR 0018 as done. Its
marks are lexical, so its counts are upper bounds; ADR 0018's first slice measured 75 cases
and gained 7, because forms such as compound subqueries and subqueries in `RETURNING` stay
out of scope.

| Group | Cases of v5 that use it | Cases clean with ADR 0018 and it | Cases of v4 that use it | Cases clean with ADR 0018 and it |
| --- | --- | --- | --- | --- |
| None (ADR 0018 alone) | | 513 | | 165 |
| Pragmas | 278 | 780 | 31 | 193 |
| Compound `SELECT` | 276 | 742 | 36 | 183 |
| Bitwise operators | 172 | 652 | 0 | 165 |
| `ALTER TABLE ... RENAME` and `DROP COLUMN` | 189 | 623 | 189 | 275 |
| Views | 208 | 609 | 135 | 232 |
| `INSERT ... SELECT` | 50 | 554 | 34 | 196 |
| `WITH` | 54 | 526 | 7 | 168 |
| Parameters | 31 | 542 | 12 | 177 |

All groups together make 1,553 cases of v5 and 508 of v4 clean (v5 has 2,324 cases out of
scope, v4 746). The pragmas that the cases of v5 run: `foreign_key_check` in 207 cases,
`integrity_check` in 142, `foreign_keys` (ADR 0018) in 74, `recursive_triggers` in 53 and
`foreign_key_list` in 10.

Facts checked on native SQLite 3.51.0:

- `PRAGMA integrity_check` on a database without damage gives one row, `ok`, in the column
  `integrity_check`.
- `PRAGMA foreign_key_check` gives one row for each child row whose parent is missing, with
  the columns `table`, `rowid`, `parent` and `fkid`, also when `foreign_keys` is off.
- `INSERT INTO t(b) SELECT b FROM t` over two rows gives four rows: SQLite reads the whole
  `SELECT` before it writes when the `SELECT` reads the written table.
- `SELECT 1 AS one UNION SELECT 2 AS two` names its column `one`, from the first `SELECT`.
- `'7' & 3` is 3 and `2.9 & 3` is 2: the bitwise operators convert their operands to
  integers.

What the code has today, after slice 1 of ADR 0018:

- **A query has one `SELECT`.** `Resolved.Query` has no compound form, and the frontend
  refuses `UNION`, `INTERSECT` and `EXCEPT`. `Source.subquery` is still a placeholder.
- **A statement reads only its own text.** Expressions have no parameter form; a script is a
  list of statements without values to bind.
- **Pragmas are not statements.** ADR 0018 D4 adds `PRAGMA foreign_keys`; no other pragma
  exists in the syntax.
- **`ALTER TABLE` adds a column.** Rename and drop are refused by the frontend; the catalog
  has no operation that changes a name.

## Decision

### D1. Parameters

- An expression may be a parameter: `?`, `?NNN`, `:name`, `@name` and `$name`, numbered as
  SQLite numbers them (a name gets the next number at its first use, `?NNN` its own). A
  statement runs with the values that its script binds to its numbers; an unbound parameter
  is NULL.
- A parameter's value has no affinity and no collation, as a literal value, but a parameter
  is never a result column number in `ORDER BY` or `GROUP BY`, and SQLite reads its value
  only when the statement runs. So resolution keeps it as an expression, and `LIMIT ?` takes
  the bound integer.
- The script carries the values, one list for each statement. ADR 0017's S3 binds them from
  `$x` and `:name` in Lean source. A corpus case binds the values that its trace records for
  each statement. (Amended 2026-10-23: the first text said that a corpus case binds none, but
  12 authored cases of v5 and 11 of v4 bind a value to each parameter, and the model marks
  them unsupported today.)
- Amended 2026-10-22: ADR 0017's S2 adds a run that resolves each statement when it runs and
  continues after an error (ADR 0017, D3, amended). That run carries the bound values too,
  and gives them to each statement that it runs.

### D2. Pragmas as statements

- `PRAGMA integrity_check` and `PRAGMA quick_check`, with their forms with a table name or a
  row limit: the row `ok` when every row satisfies the constraints that the pragma checks,
  and otherwise SQLite's rows for the failures, such as `NULL value in t.a`, in SQLite's
  order. `integrity_check` checks `NOT NULL`, `CHECK`, the unique keys and the types of a
  `STRICT` table; `quick_check` checks the same without the unique keys, as SQLite's
  documentation states. A law for each pragma relates its `ok` row to the constraint atoms
  of `Database.Valid` (ADR 0022, D1): `NotNull`, `ChecksHold`, `TypesFit` and `KeysUnique`
  for `integrity_check`, and the same without `KeysUnique` for `quick_check`. The form
  without a table name, also with a row limit, checks every table, so its law uses the
  database form of each atom. The form with a table name checks only that table and its
  indexes, and gives `ok` when another table fails a constraint, so its law uses the table
  form of each atom (`Table.NotNull` and the others) for the named table only. The pragmas run
  on any database that SQLite can reach, so each law has `Database.Admitted` as its
  hypothesis, not `Database.Valid`. The model has no damaged pages or index entries, so the
  failures that only they cause do not occur. (Amended 2026-10-22: the first text related the
  `ok` row to `LiteralData.constraints`, because `Database.Valid` did not include the
  constraints before ADR 0022.)
- `PRAGMA foreign_key_check`, with and without a table name: the rows of SQLite, over the
  foreign keys of the catalog (ADR 0014) and the checks of ADR 0018 D4.
- `PRAGMA table_info` and `PRAGMA foreign_key_list`, and their table-valued forms
  `pragma_table_info('t')` and `pragma_foreign_key_list('t')` in `FROM`, which the guide's
  schema facts use.
- `PRAGMA recursive_triggers`, with the triggers of ADR 0018 D5.
- Every other pragma stays unmodeled. A pragma statement that the model does not describe is
  refused by the frontend, as today.

### D3. Compound `SELECT`

- `UNION ALL`, `UNION`, `INTERSECT` and `EXCEPT`, from left to right, with `ORDER BY`,
  `LIMIT` and `OFFSET` on the whole compound. The result columns have the names of the first
  `SELECT`; each column compares under SQLite's collation of a compound column (the left-most
  `SELECT` whose column has one), and the duplicate rules are those of `DISTINCT` (ADR 0018
  D3).
- A compound `SELECT` may be a statement, a subquery (ADR 0018 D1) and the source of
  `INSERT` (D4). Its row order without `ORDER BY` is SQLite's plan, which the harness
  compares as a multiset and which a scalar subquery reads only when every order gives the
  same first value, as in ADR 0018 slice 1.
- Amended 2026-10-23: the collation of a compound column applies to the duplicate rule and to
  an `ORDER BY` term without `COLLATE`. Two rules of SQLite differ from it, and the model
  follows SQLite:
  - `x IN (q)` over a compound reads the affinity and the collation of the right-most
    `SELECT`'s column, and a scalar subquery `(q)` reads only its affinity, because SQLite
    gives a subquery no collation. For example, over `t(n TEXT COLLATE NOCASE)` with `'a'` and
    `u(m TEXT)`, `'A' IN (SELECT n FROM t UNION SELECT m FROM u WHERE 0)` is 0. The next item
    gives the exception to this rule.
  - When an operator is not `UNION ALL` and an `ORDER BY` term has `COLLATE`, SQLite sorts the
    compound as the subquery of `SELECT * FROM (compound)`. Then a term without `COLLATE` sorts
    under the collation of the left-most `SELECT`'s expression, `BINARY` when it has none. Also,
    `x IN (q)` then reads the column of that subquery: the collation of the left-most
    `SELECT`'s expression, and the affinity that SQLite gives to a column of a subquery in
    `FROM` (D5). A scalar `(q)` reads only that affinity, and has no collation. For example,
    `'A' IN (SELECT 'a' COLLATE NOCASE UNION SELECT 'b' WHERE 0 ORDER BY 1 COLLATE BINARY)` is
    1. Slice 3 refuses such an `IN` or scalar subquery with a restriction, and slice 4 adds it
    with the columns of a subquery in `FROM`. The result columns of such a statement have the
    names of that subquery's columns (`sqlite3ColumnsFromExprList`), which SQLite gives before it
    resolves the names, not the names of the first `SELECT`: a name or `x.c` without `AS` under
    `COLLATE` has that name as written, and a second column of the same name gets the suffix
    `:1`. For example,
    `SELECT a COLLATE NOCASE FROM t EXCEPT SELECT a FROM u ORDER BY 1 COLLATE BINARY` names its
    column `a`, and the same statement without `COLLATE BINARY` names it `a COLLATE NOCASE`.
    (Amended 2026-10-23, from a native check.)
- Amended 2026-10-23: slice 3 does not include a compound `SELECT` as a statement of a trigger
  body; the frontend refuses it. A compound subquery in a statement of a trigger body is in
  slice 3. A later slice adds the statement form when a measurement or a guide example needs
  it.

### D4. The table rebuild

- `INSERT ... SELECT`, with the conflict algorithms and `ON CONFLICT` clauses of the model.
  The model computes the rows of the `SELECT` before it writes, as SQLite does when the
  `SELECT` reads the written table, and in the order of the `SELECT`.
- `ALTER TABLE t RENAME TO u`, `ALTER TABLE t RENAME COLUMN a TO b` and
  `ALTER TABLE t DROP COLUMN a`, with SQLite's rewrite of the references in indexes, foreign
  keys, triggers and views, and its prepare errors (for example, a column of a key or an
  index cannot be dropped). Only SQLite's default, `legacy_alter_table` off, is modeled.

### D5. Queries as sources

- A subquery in `FROM` (a derived table), a view (`CREATE VIEW`, `DROP VIEW`, and a view in
  `FROM`) and a common table expression of `WITH` without `RECURSIVE` are one form: a
  resolved query as a source, which fills the `Source.subquery` placeholder.
- The rows of a source query are its result rows. When SQLite's plan can change them (a
  `LIMIT` that cuts ties, ADR 0018 slice 1), the statement is not described.
- `WITH RECURSIVE`, `INSTEAD OF` triggers and `MATERIALIZED` hints stay out of scope.

### D6. Bitwise operators

`&`, `|`, `~`, `<<` and `>>`, over SQLite's integer conversion of each operand: NULL for a
NULL operand, the shift rules of `sqlite3VdbeExec` for negative and large shift counts.

### D7. Slices and order

| Slice | Content | Needed by |
| --- | --- | --- |
| 1 | D1, parameters | ADR 0017 S3 |
| 2 | D2, pragmas | ADR 0017 S4 (schema facts) and S6 (`foreign_key_check`); after ADR 0018 slices 4 and 5 |
| 3 | D3, compound `SELECT` | ADR 0017 S4 (`EXCEPT`) |
| 4 | D5, queries as sources | the corpora; slice 5 rewrites views |
| 5 | D4, the table rebuild | ADR 0017 S6 |
| 6 | D6, bitwise operators | the corpora |

Parameters come first, because the surface's slice S3 binds them. The pragmas come next for
the largest measured gain, after the foreign keys and triggers of ADR 0018 that two of them
read. The rebuild comes after queries as sources, because a rename rewrites views. Each
slice works as in ADR 0015: an authored corpus with kernel proofs, mutants for the rules
that are easy to get subtly wrong, the verdict of every corpus, and `just test-full` at the
slice's end.

Amended 2026-10-22: slice 1 starts after ADR 0017's S2, whose run it gives the bound values,
and ends before S3. Slices 2 and 3 end before S4, and slices 4 and 5 before S6. Slice 6 has
no slice of ADR 0017 that waits for it.

## Consequences

- **The guide's lead example becomes a model example.** With ADR 0018 slice 4 and slices 2
  and 5 here, every statement of the table rebuild has a model meaning, so S6 can state and
  prove it.
- **The verdict grows by an estimate of about 1,040 cases of v5 and 340 of v4** beyond ADR
  0018, as upper bounds.
- **A script gets values.** The statements of a script read the bound values, so the laws
  over scripts quantify over them; a script without parameters reads none.
- **The catalog gets renames.** Names in the catalog can change, so the laws of unique names
  (`NamesSpec`) and catalog agreement cover rename and drop.

## Alternatives considered

**Bind parameters in the surface by substitution of literals.** It needs no model work, but
it changes meaning: `ORDER BY ?` bound to 1 sorts by a constant, and `ORDER BY 1` sorts by
the first result column. The surface never approximates (ADR 0017 D4).

**Pragmas or compound `SELECT` first.** Each makes about ten times more cases of v5 clean
than parameters do, but ADR 0017's S3 cannot start without parameters, and slices 2 and 3
come before S4, which needs them, in either order.

**Views and `WITH` before compound `SELECT`.** Views make more cases of v4 clean, but the
guide needs `EXCEPT`, and compound `SELECT` makes more cases of v5 clean.

**Every pragma.** Most pragmas change settings that the model does not have (the journal
mode, the page size, the cache). They stay out until a measurement shows a gain.

## Not decided here

- `WITH RECURSIVE`, window functions, `ORDER BY` inside an aggregate call and `FILTER`.
- Pragmas other than those of D2, and `ATTACH`.
- The details of each slice: its task file decides them from SQLite's code.

## Owner decisions

Decided on 2026-10-22:

1. **The order of D7**, parameters first.
2. **D1: parameters in the model**, not substituted by the surface.
3. **A pull request for each slice**, at the slice's end, for this ADR.

Decided on 2026-10-23:

4. **D1: the corpus runs bind the recorded values.** A corpus case gives the model the values
   that its trace records for each statement, so the authored cases that bind parameters
   become evidence for D1.
