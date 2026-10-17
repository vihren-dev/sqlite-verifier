# ADR 0012: Query semantics in the SQLite model

Date: 2026-10-13. Status: ACCEPTED on 2026-10-13.
Audience: designers and reviewers.
Related: [ADR 0005](adr-0005-conformance-corpus-scale.md),
[ADR 0006](adr-0006-model-boundary-and-execution-levels.md),
[ADR 0008](adr-0008-syntax-and-resolution-in-lean.md),
[ADR 0011](adr-0011-product-trust-and-development-integrity.md),
[conformance format v1](conformance-format-v1.md).

## Context

ADR 0008 moved statement syntax and name resolution into Lean. Its step 3 adds
`Syntax` and `resolve` for the query and expression syntax of the reference
workload of ADR 0005, section 1.3: `SELECT` with `ORDER BY`, `LIMIT` and
`GROUP BY`; `COUNT`, `SUM`, `AVG` and `MAX`; `COALESCE` and `CAST`; `RETURNING`;
`JOIN`; `ON CONFLICT`; time and JSON functions; and `REAL` arithmetic.

Resolution alone does not make this SQL useful. The frontend refuses syntax that
the model cannot run, and the model cannot run a query today:

- ADR 0006 reserves three levels for this work, "Values", "Expressions" and
  "Queries", but defines none of them. The model compares values only as integer
  equality, for unique keys and for the `WHERE column = integer` filter of an
  `UPDATE`.
- ADR 0005, section 3.1, defines how the conformance suite compares the outputs
  of a statement: result shape, typed rows, tie groups for `ORDER BY`, and the
  rules for `LIMIT` and `OFFSET` that cut a tie group. The judge implements
  these rules (`judge/outputs.py`). The model produces outputs only for literal
  `INSERT` and `UPDATE`: their change counts.

This ADR defines the semantics of the three levels, the order in which the
workload SQL enters the model, and the first slice in detail.

## Decision

### Levels

The levels of ADR 0006 get these responsibilities. Each level uses only the
levels above it in this list.

| Level | Reads and produces | First slice |
| --- | --- | --- |
| Values | Two values to an ordering; a value to a truth value | Comparison with affinity, storage-class order and BINARY collation |
| Expressions | One row to a value | Literals, columns, comparisons, `AND`, `OR`, `NOT`, `IS`, `IS NULL` |
| Queries | One table to a result: column names and rows | One table, `WHERE`, `GROUP BY`, `ORDER BY`, `LIMIT`, `OFFSET`, `COUNT`, `MIN`, `MAX` |
| Statements | A query statement to an output, with no state effect | `SELECT` in a script |

The levels are model code in `Belay.Sqlite`, beside the statement semantics.
They do not depend on the verification application (ADR 0006).

### Syntax and resolution

The layering of ADR 0008 applies without change.

- **Syntax.** `Syntax.Statement` gets a `select` constructor. `Syntax.Expr` gets
  binary and unary operators, `IS`, `IS NULL`, function calls with a name and
  arguments, and `*` as a function argument. Each result column keeps its source
  text, because SQLite uses that text as the column name (see "Output").
- **Resolution.** `resolve` turns a `select` into `Resolved.query`. It folds
  names, puts each column reference at its table position, decides if the query
  is an aggregate query, and checks the rules that SQLite checks while it
  prepares the statement. A violated rule is a prepare error with its message
  format; SQL that the model does not describe is a model restriction (R7).
- **Specification.** Each new rule of `resolve` gets a declarative statement and
  a proof that `resolve` meets it, as ADR 0008 requires.

The prepare errors of the first slice are `no such column: %s`,
`misuse of aggregate function %s()` (an aggregate in `WHERE`, or nested
aggregates), `%r ORDER BY term out of range - should be between 1 and %d`, and
`%r GROUP BY term out of range - should be between 1 and %d`.

### Values

The comparison follows "Comparison Expressions" and "Sort Order" of the pinned
`datatype3.html`. Each rule names its requirement identifier.

- **Storage classes.** NULL is less than every other value (R-08551-61977). An
  INTEGER or REAL is less than any TEXT or BLOB (R-14505-63184). A TEXT is less
  than a BLOB (R-64324-28127).
- **Numbers.** An INTEGER and a REAL compare by their exact numeric values. The
  model does not convert the integer to a double: a 64-bit integer and the
  nearest double can compare as unequal in SQLite.
- **Text.** The BINARY collation compares the UTF-8 bytes (R-53528-47027).
  Other collations are model restrictions in the first slice.
- **Affinity before a comparison.** The rules of R-10393-27560, R-58138-64688
  and R-29161-32953 apply to the operands of `=`, `<`, `<=`, `>`, `>=`, `<>`,
  `IS` and `IS NOT`. They use the affinity of a column reference and the absence
  of affinity of a literal, which `resolve` already knows.
- **NULL.** `=`, `<` and the other comparisons give NULL when an operand is NULL.
  `IS` and `IS NOT` treat two NULLs as equal (R-24731-45773).
- **Truth value.** `WHERE` keeps a row when its expression is true: a non-zero
  number. In the first slice, a `WHERE` expression is a comparison, a logical
  operator or `IS NULL`, whose value is 0, 1 or NULL. A bare column or literal
  as a condition, which needs SQLite's text-to-number conversion, is a model
  restriction.

The comparison is one Lean function. Its proofs show that it is a total
preorder on values, which the sort and the grouping need.

### Expressions

An expression evaluates against one row of one table, to a value. The first
slice has literals, column references, the six comparison operators, `IS`,
`IS NOT`, `IS NULL`, `IS NOT NULL`, `AND`, `OR` and `NOT`, with SQLite's
three-valued logic. Arithmetic, `CAST`, `COALESCE` and other functions are later
slices. No expression of the first slice can fail at run time.

### Queries

A query of the first slice reads one table and runs these steps in order:

1. **Source.** The rows of the table, in rowid order.
2. **Filter.** The rows for which the `WHERE` expression is true (R-60775-64916).
3. **Groups.** For an aggregate query (R-20637-43463), the rows are put in groups
   by the values of the `GROUP BY` terms, with the comparison above. Without
   `GROUP BY`, all rows form one group, also when there are no rows
   (R-02223-49279).
4. **Projection.** One output row per row, or per group of an aggregate query.
   `COUNT(*)` counts the rows of a group (R-13776-21310), `COUNT(x)` the rows
   where `x` is not NULL (R-34280-42283). `MIN` and `MAX` give the least and the
   greatest non-NULL value (R-16028-39081, R-52585-35928), or NULL when there is
   none.
5. **Order.** With `ORDER BY`, a stable sort by the terms, each ascending by
   default (R-18705-33393) or descending, with NULL first in ascending order
   (R-12881-55998).
6. **Window.** `OFFSET` rows are skipped and at most `LIMIT` rows are kept.

The model returns its rows in one fixed order: the rowid order of the source,
sorted stably by the `ORDER BY` terms. SQLite gives no order for rows without
`ORDER BY`, or for rows that tie under it. ADR 0005 compares such rows as
multisets and tie groups, and it compares a `LIMIT` or `OFFSET` that cuts a tie
group as a submultiset. So the fixed order of the model is not a claim about
SQLite's order, and the comparison does not depend on it.

These are model restrictions in the first slice: more than one table, `JOIN`,
subqueries, `DISTINCT`, compound `SELECT`, `HAVING`, window functions, a column
in an aggregate query that is not in `GROUP BY` and not in an aggregate (SQLite's
"bare column" rule), `LIMIT` and `OFFSET` that are not integer literals, and a
negative `OFFSET`.

### Output

A query statement produces a `StatementOutput` (conformance format v1): the
column names, the rows, and no change count. The column name of a result column
is its `AS` alias. Without an alias, it is the column name for a bare column
reference, as written in the table definition; otherwise it is the source text of
the expression, as written. These are the rules of the pinned release for the
first slice. A case where they would differ from SQLite's name is found by the
conformance suite.

### Statements and the verification target

A `SELECT` in a script has no effect on the database. The execution semantics
returns the incoming state and the output. The script semantics, positions,
first-error stopping and transactions of ADR 0006 do not change. Because a
query changes no state, `VerificationConditions` keeps its formulas: a migration
that contains a `SELECT` is verified about its state effects, as before. A
`SELECT` that fails at prepare time stops the script, as other prepare errors
do. The trust boundary does not change: resolution and evaluation are model
code that the kernel checks through the agent's proof, and the gate compares the
resolved script as before.

### Testing

The rules are checked in the ways ADR 0008 uses for resolution:

- **Conformance.** Corpus records of version 3 and later carry statement
  outputs. Once the model produces outputs for queries, the judge compares them
  with the rules of ADR 0005, section 3.1. Cases that agree become `mustAgree`
  claims in an owner-approved judge change (ADR 0011).
- **Authored coverage cases.** For each rule: a case where it applies, a
  neighbor where it does not, and boundary values: integer and real ties,
  storage-class order between NULL, numbers, text and blobs, NULL in each
  operand of each operator, an empty table with and without `GROUP BY`, a
  `LIMIT` that cuts a tie group, and each prepare error.
- **Mutants.** Each must change the verdict of a case: NULL equal to NULL under
  `=`; an integer compared with a real through a double; text compared without
  case; `DESC` ignored; NULL last in ascending order; `COUNT(x)` counting NULL;
  `MIN` over NULL; an empty table giving no row for `COUNT(*)`; `LIMIT` one too
  high; `OFFSET` ignored; and each prepare error removed.
- **Proofs.** The filter keeps exactly the rows whose condition is true. The
  result of `ORDER BY` is sorted by the terms and is a permutation of its input.
  The window has the length that `LIMIT` and `OFFSET` give. `COUNT(*)` of a
  group equals its number of rows.

### Slices

Each slice is one task with the work of ADR 0008: syntax, resolution with its
specification, semantics, conformance cases, mutants and a judge change.

1. **Single-table queries.** As this ADR describes.
2. **Numbers.** `REAL` and integer arithmetic, with SQLite's integer overflow to
   REAL; `CAST`; `COALESCE`; `SUM` and `AVG`, with the `integer overflow` error
   of `SUM` and the summation of the pinned release.
3. **Writes with output.** `RETURNING` (compared as a multiset, ADR 0005), and
   `INSERT` and `UPDATE` with expressions instead of literals.
4. **Joins.** Inner and left joins of tables, with qualified names and the
   `ambiguous column name` error.
5. **Conflicts.** `ON CONFLICT` of `INSERT`. Amendment 4 splits it into unique keys
   (5a, 5b) and conflicts (5c, 5d).
6. **Functions.** Time and date functions, which need the controlled clock of
   ADR 0005, section 3.2, and the JSON functions `json_extract` and `json_each`.
   Amendment 5 splits it into queries without `FROM` (6a), JSON slices (6b to 6d) and
   time slices (6e to 6g).

The order puts the shared value and expression work first and the functions
with the most separate rules last. A slice may change the order of later slices
when its evidence shows a reason.

## Consequences

- **Model.** The Values, Expressions and Queries levels of ADR 0006 exist, with
  proofs. Later slices extend them instead of adding parallel evaluators.
- **Frontend.** The mapping to `Syntax` grows by one constructor per form, and
  keeps the source text of each result column. It still refuses every form that
  the model does not run.
- **Conformance.** Queries in the frozen corpora move from `MODEL_UNSUPPORTED`
  to compared, slice by slice. A disagreement found this way is a model bug or a
  wrong rule of this ADR; each one is fixed before its cases are claimed.
- **Verification.** Migrations that contain queries become admissible; their
  verification targets are unchanged.
- **Cost.** Kernel proofs of conformance cases with queries evaluate the query
  in the kernel. Cases stay small, as for resolution.

## Alternatives considered

**Evaluate queries in Python.** Rejected for the reasons of ADR 0008: it would
be trusted code with no formal statement, outside the model that the proofs use.

**Use SQLite as the oracle at verification time.** Rejected: the verifier does
not run the application's SQL, and the model must say what a query returns for
every admitted database, not for one recorded state.

**All workload SQL in one step.** Rejected: the value and expression rules are
shared by all later forms, and each form has rules of its own. One step would
delay the first evidence and make each review larger.

**Model SQLite's order of rows without `ORDER BY`.** Rejected: SQLite does not
specify it, it depends on the query plan, and ADR 0005 already compares such
results without it.

## Not decided here

- Collations other than BINARY, and the `COLLATE` operator.
- The text-to-number conversion of a bare value used as a condition.
- Subqueries, compound `SELECT`, `DISTINCT`, `HAVING` and window functions.
- Triggers and foreign-key actions, which run statements inside statements and
  need the fuel and transaction rules that ADR 0006 asks for.

## Amendment 1: Row-dependent writes (slice 3b)

Date: 2026-10-14. Status: ACCEPTED (2026-10-14, #111).
Related: the slice 3a task, plans/20261014-writes-with-output.task.md.

### Context

The owner narrowed slice 3 to slice 3a: constant expressions folded at resolution,
and `RETURNING`. In slice 3a, writes stay literal, and a value that the affinity
would convert is a model restriction (`LiteralData.lossless`). This amendment
decides slice 3b: `SET` values that read the row (`SET v = v + 1`), an `UPDATE`
filter that is any condition of slices 1 and 2, and store-time affinity.

### Resolved forms

- **`UPDATE`.** `Resolved.Statement.update` keeps one constructor, with assignments
  `List (Nat × Resolved.Expr)` and filter `Option Resolved.Expr`. The literal update
  of slice 3a is a special case: `.literal` values and the filter
  `.compare .eq (.column p) (.literal (.integer n))`. No second evaluator exists.
- **Resolution.** `resolveUpdate` resolves each `SET` value and the `WHERE`
  condition with the expression resolution of `SELECT`, with the table's columns in
  scope. The affinity rules of a comparison, the prepare errors (`no such column`,
  `misuse of aggregate function`) and the restrictions of slices 1 and 2 apply
  without change. A constant expression folds to `.literal` of its stored value.
- **Key columns.** A `SET` value that reads the row may not assign a key column:
  this is a model restriction (owner decision of 2026-10-14, question 1 below). A
  key column takes a constant, as in slice 3a.
- **`INSERT`.** `VALUES` cannot read a row: SQLite reports `no such column`. So
  `Resolved.Statement.insert` stays literal. Resolution applies the column affinity
  to each value and to each default, and stores the result.

### Store-time affinity

SQLite applies the column affinity to each value that it writes (`applyAffinity`
in `OP_MakeRecord`, SQLite 3.51.0). The rules of the pinned `datatype3.html`:

| Affinity | Rule |
| --- | --- |
| TEXT | An INTEGER or REAL becomes TEXT (R-54378-38553); a REAL keeps 15 significant digits (R-25142-32967). NULL, TEXT and BLOB stay (R-21926-12440). |
| NUMERIC, INTEGER | The two are the same (R-15334-58407). A TEXT that is a well-formed integer or real literal becomes INTEGER or REAL, INTEGER first (R-12079-51392, R-36476-47203, R-05192-57965). Integer text outside 64 bits becomes REAL (R-27233-06819). Hexadecimal text and other TEXT stay TEXT (R-47301-17448). A REAL that is exactly an integer becomes INTEGER (R-22849-20349). |
| REAL | As NUMERIC, then an INTEGER becomes REAL (R-18885-42713). |
| BLOB | No change (R-03366-15091). |

- **Decision.** The model applies these rules instead of restricting them. A new
  Values-level function `storeValue : Affinity → Value → Value` ports
  `applyAffinity`, `applyNumericAffinity`, `alsoAnInt` and
  `sqlite3VdbeIntegerAffinity` with the slice 2 conversions (`atof`, `atoi64`,
  `realToI64`, `realSameAsInt`, `realText`).
- **Not `CAST`.** `castValue` converts also when the result loses information
  (R-59532-48165): `CAST('abc' AS INTEGER)` is 0, but INTEGER affinity keeps
  `'abc'`. `sqlite3VdbeIntegerAffinity` also excludes the least and greatest
  64-bit integers. So `storeValue` is a separate function.
- **REAL columns.** SQLite writes a whole REAL as an integer on disk and reads it
  back as REAL (R-31757-07599, R-59544-00330, `OP_RealAffinity`). The model stores
  the value as SQLite reads it: a REAL.
- **Admission.** `lossless` is removed as a restriction. `insertReady` requires
  `storeValue a v = v` for each stored value instead. Resolution makes this true.

### Execution

`LiteralData.updated` becomes the update of slice 3b; `checkedWrite` stays.

1. **Rows.** For each row in table order, the filter is evaluated on the old row.
   The row is selected when the value is true (`truthy`, R-58095-46013). NULL and
   false do not select it. Without a filter, every row is selected (R-55869-30521).
2. **Values.** Each `SET` value is evaluated on the old row of a selected row,
   also when an earlier assignment writes a column that it reads (R-36239-04077,
   R-40598-36595). `storeValue` with the column affinity gives the stored value.
   Other columns and the rowid do not change (R-40472-60438).
3. **Constraints.** `checkedWrite` checks NOT NULL and the unique keys on the
   table after the write. On a failure, it keeps the input database: ABORT backs
   out the whole statement (R-55069-12282, R-47224-48532). This is the only
   run-time error: no expression of slices 1 and 2 fails outside an aggregate, and
   an aggregate in `SET` or `WHERE` is a prepare error.
4. **Output.** The change count is the number of selected rows; zero is not an
   error (R-58129-20729). `RETURNING` of slice 3a reads the new rows.

SQLite checks each row when it writes it, in an order that it does not specify
(R-10927-26133). With a row-dependent key value, the result can depend on that
order: `SET k = k + 1` over the keys 1 and 2 fails or succeeds by plan. Key
values are constants (see "Resolved forms"), and then a check after the write
agrees with every order: a constant key for two or more selected rows collides in
every order, and for one row it collides only with a row that keeps its key.

### Data-domain obligations and the verification target

`statementReady` keeps its form. `updateReady` requires these conditions:

- `tableReady keys table` before the write, and each assignment names a column.
  These do not change.
- Each key position is `comparisonReady` in the table after the write. The formula
  and its meaning do not change, because key values are constants.
- **Removed:** `comparisonReady` at the filter position and the integer filter
  value. The Values level computes the comparison with SQLite's rules.

`insertReady` changes only from `lossless` to `storeValue a v = v`. `Conforms`,
which defines the admitted databases with the approved conditions, gains stored
form: every cell equals `storeValue` of itself for its column (question 5).

**Verification target.** `VerificationConditions` keeps its formulas, and
`Contract.lean` can stay unchanged: it names `SupportedSql` and `ProfileExecutes`
from `SqlExecution.lean`, whose types do not change. The field `ready` still
requires `SupportedSql` for every admitted database, as a proof obligation, not a
premise. The obligations now depend on the values that an `UPDATE` reads, so a
proof of `ready` can need an approved condition about those values. The meaning of
`ready` changes in files that are not owner-reviewed. They stay outside CODEOWNERS
(question 3): like the rest of the model, they are checked by evidence. Each
conjunct of `insertReady`, `updateReady` and `statementReady` that a database state
can violate after resolution has a mutant, and a claimed boundary case, with a
database state just outside the domain, disagrees when the conjunct is removed.
Each other conjunct names the restriction that resolution reports first, or the
reason that no boundary case exists (`conformance/obligation_mutants.py`).

### Restrictions that remain

- Unique keys over TEXT or REAL columns, and key values other than integer or
  NULL. A `SET` value that reads the row for a key column (question 1).
- `INTEGER PRIMARY KEY` rowid aliases; a column assigned twice in `UPDATE`.
- `INSERT OR`, `UPDATE OR`, UPSERT (slice 5); `UPDATE … FROM`; `ORDER BY` and
  `LIMIT` on `UPDATE`; `INSERT … SELECT`; subqueries; parameters.
- A bare column or literal as a condition; collations other than BINARY.
- Triggers and foreign-key actions. `DELETE` until slice 3c (question 6).

### Testing

- **Authored coverage cases.** `storeValue` for each affinity and each storage
  class, with neighbors: `'3.0e+5'`, `' 12 '`, `'0x10'`, `'abc'`,
  `'9223372036854775808'` and `'1e400'` into INTEGER, NUMERIC and REAL; 5.0, 5.5
  and `2^63` as REAL into INTEGER; an integer and `2^53 + 1` into REAL; a REAL into
  TEXT; a BLOB into each. `UPDATE`: `SET v = v + 1`; `SET a = b, b = a`; a filter
  that is NULL for some rows; `AND`, `OR`, `IS` and `IS NULL` filters; no match; a
  NOT NULL failure from a NULL cell; a unique failure after `SET k = 5` over two
  rows; `SET k = k + 1` (a restriction); a failure after some rows match, with
  `RETURNING`; an integer overflow to REAL in a non-key column.
- **Mutants.** Each must change the verdict of a case: `SET` values read the new
  row; a NULL filter selects the row; no store affinity; `castValue` as store
  affinity; a REAL column keeps an integer; a TEXT column keeps a number; a failed
  `UPDATE` keeps the rows before the failing one; the change count counts every row.
- **Obligation mutants and boundary cases.** Each conjunct of the admission
  obligations that a database state can violate after resolution has a mutant that
  removes it, and a boundary case whose database state is just outside the domain:
  `MODEL_UNSUPPORTED` with the conjunct, `DISAGREE` without it. Each other conjunct
  names what covers it, as "Data-domain obligations" says. For example, a REAL that equals an integer in a unique key. The
  boundary cases are frozen and claimed through the judge, so a weakened obligation
  fails the verdict. The boundary case of the slice 3a filter obligation, `1.0` in a
  column without affinity under the filter `c = 1`, becomes an ordinary coverage
  case when slice 3b removes that obligation: the model must agree that SQLite
  updates the row.
- **Proofs.** Every statement of the model keeps `Conforms`, including stored form
  (question 5). `storeValue` is idempotent, and its result for TEXT affinity is never
  a number. The update changes only selected rows, only at assigned positions, and
  keeps rowids and order. The update of slice 3a is the special case of literal
  assignments, so the existing preservation proofs carry over. With constant key
  values, row-by-row checks in every order give the result of `checkedWrite`.

### Slices

Item 3 of "Slices" becomes three items. **3a. Writes with output** is the narrowed
slice of the owner. **3b. Row-dependent writes** is this amendment. **3c. DELETE**
follows 3b: `DELETE FROM table [WHERE condition] [RETURNING columns]` with the
filter of 3b, its change count and its `RETURNING` rows. Items 4 to 6 do not change. Slice 5 (`ON CONFLICT`) uses the expressions of slice 3b in
`DO UPDATE SET`.

### Alternatives considered

- **Keep the conversion a restriction.** Rejected: the workload writes text into
  numeric columns, and slice 2 already has the conversions.
- **Store with `castValue`.** Rejected: CAST and affinity differ (see above).
- **Row-by-row checks in rowid order.** Rejected: SQLite does not specify the
  order, and a plan with an index visits rows in another order.
- **A second constructor for row-dependent `UPDATE`.** Rejected: two evaluators
  for one statement, against the "Consequences" of this ADR.

### Owner decisions

1. **Key columns.** Decided on 2026-10-14: a row-dependent `SET` value for a key
   column is a model restriction. Row-dependent writes to keys are rare in
   migrations, and the restriction keeps the key obligations of slice 3a.
2. **Order-dependent unique failures.** Resolved by question 1: with constant key
   values, no result depends on the order of rows.
3. **Owner review of obligations.** Decided on 2026-10-14: no CODEOWNERS change.
   The obligations are model code like the rest of the model, so evidence checks
   them: obligation mutants and claimed boundary cases (see "Testing"). The
   obligations of slice 3a get the same mutants and cases before slice 3b.
4. **Filter obligation.** Decided on 2026-10-14: removed. It guarded the tagged
   value test of the slice 3a filter, which slice 3b replaces with SQLite's
   comparison; `SELECT` has no such obligation either. The key obligations stay,
   because uniqueness is still an integer test (`keyEqual`).
5. **Stored form.** Decided on 2026-10-14: `Conforms` requires every cell in its
   stored form, `storeValue affinity cell = cell` for its column. Admitted databases
   over-approximate the databases reachable through SQLite: each invariant in
   `Conforms` (unique rowids, rowids in range, one cell per column, and now stored
   form) is a guarantee of SQLite's normal write path, which is an assumption of the
   trust boundary (`docs/trust-boundary.md`). A preservation theorem shows that the
   model's statements keep every invariant; its key lemma is that `storeValue` is
   idempotent. An invariant may join `Conforms` only if it holds for every database
   that SQLite can reach. A property of the databases that the model's own statements
   can reach (for example, no REAL value in an INTEGER column) must never be used to
   admit a database, so the model defines no such notion.
6. **`DELETE`.** Decided on 2026-10-14: its own slice, 3c, right after 3b. It
   reuses the filter of 3b, keeps 3b focused, and makes migrations that delete
   rows, where application data is lost, verifiable early.

## Amendment 2: Joins (slice 4)

Date: 2026-10-14. Status: ACCEPTED (2026-10-14, #119).
Related: "Slices", item 4; "Queries"; the slice 1 task,
plans/20261013-single-table-queries.task.md.

### Context

Item 4 of "Slices" names inner and left joins, qualified names and the
`ambiguous column name` error. The rest of this ADR describes a query over one
table: `Resolved.Query` holds one table position, an expression names a column by
its position in that table, and more than one table is a restriction. This
amendment decides the joined source and the names of slice 4, and the owner's
decisions at the end add slices 4b and 4c.

### Source

- **Forms.** `FROM` is a list of table references joined left to right
  (R-28760-53843): `,`, `JOIN`, `INNER JOIN` and `CROSS JOIN` with an optional
  `ON` condition, and `LEFT [OUTER] JOIN` with an `ON` condition. The four inner
  forms are the same join (R-46256-57243, R-25071-21202). A table reference is a
  table name with an optional alias (`t AS x` or `t x`).
- **Rows.** An inner join is the cartesian product of its inputs, left columns
  first (R-44414-54710, R-59089-25828), filtered by the `ON` condition when there is
  one (R-38465-03616, R-49872-03192). A left join adds, for each left row that no
  right row matches, the left row with NULL in every right column (R-24610-05866).
  The `WHERE` filter then applies to the joined rows, so a condition on the right
  table in `WHERE` removes the padded rows, and the same condition in `ON` keeps
  them.
- **Resolved form.** `Resolved.Query` holds a source: the first table position and a
  list of joins, each with its kind, its table position and its optional `ON`
  condition. A joined row is the concatenation of the cells of its tables, and an
  expression names a column by its position in that concatenation. The evaluation
  of expressions, groups, projection, order and window of "Queries" does not
  change; the single-table query is the special case with no joins.
- **Order.** The model's fixed order is the nested order of the source: left rows in
  rowid order, and for each left row the matching right rows in rowid order. As for
  one table, this order is not a claim about SQLite's order: rows without
  `ORDER BY`, and ties under it, are compared as multisets (ADR 0005).
- **Comparisons.** `ON` conditions are expressions as in `WHERE`, with the same
  affinity rules and restrictions, applied to the operands as written.

### Names

- **Sources.** Each table reference has a name: its alias, or else its table name.
  A qualified name `x.c` names column `c` of the source named `x`; with an alias,
  the table name no longer names the source (`SELECT t.a FROM t AS x` is
  `no such column: t.a`). A qualifier that names no source is `no such column: x.c`.
- **Unqualified names.** An unqualified column name is resolved in all sources. In
  exactly one source, it names that column. In two or more, it is SQLite's
  `ambiguous column name: c`, also inside `ON`.
- **Result columns.** `*` is every column of every source, in order, each named by
  its column name; `x.*` is every column of source `x`, and `x.*` for a name that
  names no source is `no such table: x`. A qualified bare column `x.c` is named `c`.
- **Clauses.** Qualified and unqualified names work the same in `WHERE`, `ON`,
  `GROUP BY`, `ORDER BY`, aggregates and result columns.

### Verification target

Queries change no state, so the execution semantics, `statementReady` and the
verification target do not change. Writes keep one table: `UPDATE … FROM` and
joins in `DELETE` stay refused.

### Testing

- **Authored coverage cases.** Each join form; an inner join with no match, one
  match and several matches per row; a left join with unmatched left rows, with a
  right-table condition in `ON` and the same condition in `WHERE`; three tables;
  a self-join with aliases; qualified and unqualified names, `*` and `x.*`;
  aggregates and `GROUP BY` over a join; `ORDER BY` a qualified name; the prepare
  errors `ambiguous column name`, `no such column: x.c` and `no such table: x`.
- **Mutants.** Each must change the verdict of a case: a left join drops unmatched
  rows; a left join pads with the left row's values instead of NULL; `ON` is applied
  after the padding (as `WHERE`); an unqualified name takes the first source
  instead of the ambiguous error; an alias leaves the table name usable; `*` omits
  the columns of the right source.
- **Proofs.** The single-table query is the special case with no joins, so the
  existing query laws carry over; a joined row has the sum of the widths of its
  tables.

### Open questions

1. **`USING` and `NATURAL`.** Decided; see "Owner decisions".
2. **`RIGHT` and `FULL` joins.** Decided; see "Owner decisions".
3. **Two sources with the same name.** Decided; see "Owner decisions".
4. **Size.** Decided; see "Owner decisions".

### Owner decisions

1. **`USING` and `NATURAL`.** Decided on 2026-10-14: both are modeled, in a slice
   4b right after slice 4; slice 4 refuses them as model restrictions. SQLite merges
   the named columns: the right column is omitted from `*` (R-57047-10461), and an
   unqualified name refers to the left one; `t.a` and `u.a` still name both columns.
   `USING (a)` compares the left-most column `a` of the left input with the right
   column, and an unqualified `a` that names two left columns stays
   `ambiguous column name: a`. A name in `USING` that is not in both inputs is
   `cannot join using column a - column not present in both tables`; `NATURAL` with
   `ON` or `USING` is `a NATURAL join may not have an ON or USING clause`; `NATURAL`
   without a common column is a cross join. Slice 4b adds no evaluation: its joins
   are inner and left joins with a generated `ON` condition.
2. **`RIGHT` and `FULL` joins.** Decided on 2026-10-14: both are modeled, in a slice
   4c right after slice 4b; slices 4 and 4b refuse them as model restrictions. A
   right join adds, for each right row that no left row matches, the right row with
   NULL in every left column (R-15753-04279); a full join adds both kinds of row
   (R-18902-30764). With `USING`, an unqualified name of a merged column in a right or
   full join is the value of whichever input is present, as `coalesce(left, right)`:
   checked on 3.51.0, `SELECT a FROM t FULL JOIN u USING (a)` gives the right row's
   `a` for a right row that no left row matches. Slice 4c comes after 4b so that
   this rule is decided with the rest of `USING`.
   Amendment 3 corrects this decision: in a right join the name is the right column,
   and only in a full join is it `coalesce(left, right)`.
3. **Two sources with the same name.** Decided on 2026-10-14: a model restriction.
   `FROM t, t` and `FROM t AS x, u AS x` are refused with the range of the second
   source; a self-join names its sources with different aliases. SQLite prepares such
   a query and reports a column of both with the schema name, as
   `ambiguous column name: main.t.a`, which the model does not reproduce.
4. **Size.** Decided on 2026-10-14: no limit beyond SQLite's. A join of 64 tables
   runs; a 65th table is SQLite's prepare error `at most 64 tables in a join`
   (checked on 3.51.0). The authored coverage cases, which have kernel proofs, stay
   small: two or three tables with a few rows each.

## Amendment 3: RIGHT and FULL joins (slices 4c and 4d)

Date: 2026-10-15. Status: ACCEPTED (2026-10-15, #124).
Related: Amendment 2, owner decision 2, which this amendment corrects; ADR 0005 for
the comparison of rows; the slice 4b task, plans/20261015-using-natural.task.md.

### Context

Owner decision 2 of Amendment 2 says that with `USING` an unqualified name of a merged
column in a right or full join is `coalesce(left, right)`. Native SQLite 3.51.0
differs, and the model follows SQLite (owner decision, 2026-10-15):

- In a `RIGHT JOIN … USING`, the name is the right column, with its affinity. With
  `t(a INTEGER)` and `r(a REAL)`, `SELECT a FROM t RIGHT JOIN r USING (a)` gives the
  REAL `1.0`, and `WHERE a = '3'` matches an INTEGER `3`.
- In a `FULL JOIN … USING`, the name is `coalesce(left, right)`, which has no
  affinity: `WHERE a = '3'` does not match an INTEGER `3`.
- When `FROM` has a `RIGHT` or `FULL` join anywhere, the left side of the generated
  condition of every `USING` and `NATURAL` join, also one before the right join, is
  the coalesce of every column of that name in the left input, not the left-most
  column. A left table whose column of that name is not a `USING` or `NATURAL` column
  of its own join makes the query SQLite's prepare error
  `ambiguous reference to a in USING()`: `t JOIN u ON 1 RIGHT JOIN v USING (a)` and
  `t JOIN u ON 1 JOIN v USING (a) RIGHT JOIN r ON 1` both fail.

These rules change the names of slice 4b only when a right or full join is present, so
they are a slice of their own (4d), after the rows of right and full joins (4c).

### Rows (slice 4c)

- **Forms.** `RIGHT [OUTER] JOIN` and `FULL [OUTER] JOIN` with an `ON` condition, or
  with none, in any position of the join list.
- **Rows.** A right join is the inner join of its left input (all earlier sources) and
  the joined table, plus, for each row of the joined table that no row of the left input
  matches, that row with NULL in every column of the left input (R-15753-04279). A full
  join adds both the unmatched left rows of a left join and the unmatched right rows
  (R-18902-30764). `WHERE`, groups, aggregates, projection, `ORDER BY` and the window
  work on the joined rows as before.
- **Order.** The model's fixed order is the order of the inner part, then the unmatched
  right rows in rowid order. As for every join, rows without `ORDER BY`, and ties under
  it, are compared as multisets (ADR 0005).
- **Names.** Qualified and unqualified names, `*` and `x.*` work as for inner and left
  joins; a qualified column of a padded table is NULL.
- **Restrictions.** In slice 4c, `USING` or `NATURAL` anywhere in a `FROM` that has a
  `RIGHT` or `FULL` join is a model restriction until slice 4d. An `ON` condition that
  names a later table stays the restriction `later-table-in-on`; with a later right
  join, SQLite refuses it with `ON clause references tables to its right`.

### Names with USING and NATURAL (slice 4d)

- **RIGHT.** In a right join with `USING` or `NATURAL`, an unqualified merged name, and
  the merged column of `*`, is the right column, with its value and affinity; `*` names
  it by the left column's name as declared.
- **FULL.** In a full join, it is `coalesce(left, right)`, with no affinity.
- **Generated condition.** When `FROM` has a right or full join, the left side of each
  generated equality is the left column if exactly one left table has the name, and
  otherwise the coalesce of all of them, in order; every such table after the first
  must merge the name by its own `USING` or `NATURAL`, or the query is
  `ambiguous reference to a in USING()`.
- **Errors.** The prepare errors of slice 4b apply unchanged.

### Testing

- **Slice 4c cases.** Right and full joins with matched and unmatched rows on both
  sides, with no `ON`, with `ON` true for no row, after an inner and a left join, before
  a left join, two full joins in a row; `WHERE` on a padded column; aggregates
  (`count(t.a)` against `count(*)`); qualified names of padded tables; `*` and `x.*`;
  the restriction for `USING` with a right join.
- **Slice 4c mutants.** A right join drops unmatched right rows; a right join pads the
  right row's own columns instead of the left input's; an unmatched right row is
  decided per left row instead of over the whole left input; a full join omits the
  unmatched left rows.
- **Slice 4d cases and mutants.** The examples of "Context": the right column and its
  affinity, the coalesce and its missing affinity, the coalesced left side of a later
  `USING`, and `ambiguous reference to a in USING()`, each with a mutant that uses the
  slice 4b rule instead.
- **Proofs.** A joined row of a right or full join has the width of its tables; a full
  join keeps every left row and every right row; a query without right or full joins
  evaluates as before.

### Owner decisions

1. **Correction of Amendment 2, decision 2.** Decided on 2026-10-15: the model
   conforms to SQLite, and the specification is amended where it differs. Its
   sentence on `coalesce(left, right)` is replaced by "Names with USING and NATURAL
   (slice 4d)".
2. **Split.** Decided on 2026-10-15: slice 4c models the rows of right and full joins
   with `ON`; slice 4d models `USING` and `NATURAL` in a `FROM` with a right or full
   join, which slice 4c refuses as a model restriction.

## Amendment 4: Unique keys and conflicts (slices 5a to 5d)

Date: 2026-10-15. Status: ACCEPTED (2026-10-15, #131).
Related: "Slices", item 5; Amendment 1 (keys, `rowDependentKey`); ADR 0008 (key domain
and conflict mode); ADR 0005 for `RETURNING` and change counts.

### Context

Item 5 of "Slices" names `ON CONFLICT` of `INSERT`. Today the model has one conflict
behavior: a duplicate key or a NULL in a NOT NULL column is SQLite's ABORT, and the
statement fails with the database unchanged. Unique keys hold only integers and NULL
(the restrictions `key-affinity` and `key-value`), and an `INTEGER PRIMARY KEY` rowid
alias is the restriction `rowid-alias`. Those are the usual targets of a conflict
clause, so the owner decided (2026-10-15) that a keys slice comes first. SQLite has three
conflict features, all checked on native 3.51.0: the UPSERT clause, the `OR` clause of
`INSERT`, and the `ON CONFLICT` clause of a constraint in `CREATE TABLE`.

### Key values (slice 5a)

- **Equality.** A unique key compares the stored values of its columns, after the
  column's affinity (`storeValue`). Two rows conflict when no key cell is NULL and each
  pair of cells is equal under SQLite's comparison with the BINARY collation
  (`compareValues`): numbers by value, so integer `1` and real `1.0` conflict, also in a
  column without affinity; TEXT and BLOB by bytes, so `'a'` and `'A'` do not; values of
  different storage classes never, so `1` and `'1'` do not in a column without affinity.
- **Forms.** Keys of every affinity, single or composite, from `PRIMARY KEY` (other than
  a rowid alias), `UNIQUE` and `CREATE UNIQUE INDEX`. The restrictions `key-affinity` and
  `key-value` leave the registry. A key whose column has a collation other than BINARY
  stays refused, as collations are not decided here.
- **Obligations.** The key conjuncts of `statementReady` that require integer or NULL
  cells change to the new equality; obligation mutants and boundary cases follow them.

### Rowid aliases (slice 5b)

- **Form.** A column `INTEGER PRIMARY KEY` (not `DESC`) is the rowid of its table.
  Reading it reads the rowid; its uniqueness is the rowid's.
- **Values.** On `INSERT`, NULL or an omitted value gives the next rowid, as for a table
  without an alias. Another value takes INTEGER affinity and must then be an integer:
  `'5'` and `5.0` store `5`; `7.5` and `'x'` are SQLite's `datatype mismatch` error
  (`SQLITE_MISMATCH`). A duplicate is `UNIQUE constraint failed`. `UPDATE` of the alias
  moves the row to the new rowid, with the same rules. The restriction `rowid-alias`
  leaves the registry; the rowid names (`rowid-name`) are not part of this slice.

### UPSERT (slice 5c)

- **Forms.** `INSERT INTO t … VALUES … ON CONFLICT [(columns)] DO NOTHING` and
  `… DO UPDATE SET assignments [WHERE condition]`, with one or more such clauses; only
  the last may omit its target. A target is a set of columns, in any order and compared
  without ASCII case, equal to the columns of one key; another target is SQLite's
  prepare error `ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint`.
- **Rows.** The rows of `VALUES` are processed in order, so a later row sees the rows
  that earlier ones inserted or updated. A row that conflicts on the target key of a
  clause is handled by the first such clause; a row that conflicts only on keys that no
  clause targets is the ABORT error, unless a clause without target handles it. `DO
  NOTHING` skips the row. `DO UPDATE` updates the one existing row of the conflict; its
  values and `WHERE` read that row (by column name, table name or alias) and the
  proposed row as `excluded.c`, after the column's affinity. A `WHERE` that is not true
  skips the row. The updated row is checked against every key and NOT NULL; a failure is
  the ABORT error of the statement.
- **Output.** `RETURNING` returns each inserted row and each updated row with its new
  values, not the skipped ones; the change count counts both.
- **Restrictions.** A clause without target with `DO UPDATE` on a table with more than
  one key is a model restriction: SQLite then chooses the conflicting key by its internal
  order of indexes (owner decision, 2026-10-15). `INSERT … SELECT` stays refused.

### `INSERT OR` and constraint algorithms (slice 5d)

- **Algorithms.** `INSERT OR ABORT` is today's behavior. `OR FAIL` stops at the row with
  the error and keeps the earlier rows of the statement (R-31882-08811). `OR ROLLBACK`
  fails and rolls back the active transaction (R-31881-13880), or works as ABORT without
  one (R-42089-41020). `OR IGNORE` skips each row that violates a key or NOT NULL
  (R-50299-05307). `OR REPLACE` deletes every existing row that the new row conflicts
  with, on any key, before it inserts the row (R-54702-17780); a NULL in a NOT NULL
  column takes the column's default, or is ABORT without one (R-12527-00403); the deleted
  rows are not counted (R-37019-57602). `RETURNING` returns the inserted rows.
- **Constraint algorithms.** The `ON CONFLICT` clause of a `PRIMARY KEY`, `UNIQUE` or
  `NOT NULL` constraint in `CREATE TABLE` is the default algorithm of that constraint;
  an `OR` clause overrides it (R-33948-22286), and an UPSERT clause handles the conflicts
  of its target before it.
- **Out of scope.** `UPDATE OR`: which rows it skips or replaces depends on SQLite's
  unspecified order of rows, as for row-dependent keys (Amendment 1).

### Testing

- **Cases.** Each rule above with native SQLite as the oracle: equal and unequal keys
  of each affinity and storage class, composite keys and NULL; rowid alias values,
  `datatype mismatch` and `UPDATE` of an alias; each UPSERT form, several clauses, a
  later row that conflicts with an earlier one, `excluded`, `WHERE`, a second key that
  fails after `DO UPDATE`, `RETURNING` and change counts; each `OR` algorithm, also in a
  transaction, and each constraint algorithm with its precedence.
- **Mutants.** For each slice, one per rule that a wrong model could change, such as a
  key that compares text without bytes, a rowid alias that keeps `7.5`, a `DO UPDATE`
  that updates the first row instead of the conflicting one, an `excluded` value without
  affinity, `OR REPLACE` that deletes only one conflicting row, and `OR FAIL` that keeps
  no row.
- **Proofs.** Each write keeps `Conforms`; the integer keys of today are a special case
  of the new equality; a statement without conflict clauses keeps its current
  semantics.

### Open questions

1. **Two key slices.** Decided; see "Owner decisions".

### Owner decisions

1. **Scope.** Decided on 2026-10-15: two conflict slices, the UPSERT clause (5c) and the
   `OR` clause with constraint algorithms (5d).
2. **No-target `DO UPDATE`.** Decided on 2026-10-15: a model restriction on a table with
   more than one key; see "UPSERT (slice 5c)".
3. **Keys first.** Decided on 2026-10-15: the key slices come before the conflict
   slices.
4. **Two key slices.** Decided on 2026-10-15: the keys work is two slices, 5a (key
   values) and 5b (rowid aliases). They change different parts of the model: key
   equality and its obligations, and the storage of a row.

## Amendment 5: Functions and queries without FROM (slices 6a to 6g)

Date: 2026-10-16. Status: ACCEPTED (2026-10-16, #141).
Related: "Slices", item 6; "Not decided here" (table-valued functions); ADR 0005,
section 3.2 (the controlled clock); ADR 0006 (levels); ADR 0008 (restrictions).

### Context

Item 6 of "Slices" names the date and time functions and the JSON functions
`json_extract` and `json_each`. Today the model evaluates literals, column references,
comparisons, logic, arithmetic, `CAST`, `COALESCE` and the aggregates of slice 2. Every
other function is the restriction `unmodeled-function`. The time keywords and a
`CURRENT_TIMESTAMP` default are the restriction `time-value`. The frontend refuses a
`SELECT` without `FROM` and a table-valued function in `FROM`.

The verdict of 2026-10-16 (after slice 5d) has 5,777 cases outside the model's scope in
the claimed corpora. Of the reasons that this amendment addresses, a `SELECT` without
`FROM` keeps 485 cases out, the upstream `json101` cases 219, `func2` 131, `func7` 72,
and other unmodeled functions 100. Many upstream tests of functions use `SELECT`
without `FROM`, so that form comes first.

All facts below were checked on native SQLite 3.51.0.

### Queries without FROM (slice 6a)

- **Form.** `SELECT result-columns [WHERE condition] [ORDER BY ...] [LIMIT ...]`
  without `FROM`. The source is one row with no columns: the query returns one row, or no
  row when the `WHERE` condition is not true. Aggregates read that one row:
  `SELECT count(*)` is 1. A column name is `no such column`.
- **Model.** A source with one empty row at the Queries level; resolution has a scope
  with no sources. No new evaluator.
- **Why first.** It is small, it admits the upstream tests that call functions without a
  table, and it gives slices 6b to 6g their cases.

### JSON reading and `json_extract` (slice 6b)

- **Functions.** `json_extract(json, path, ...)` and the operators `->` and `->>`.
- **Reading.** The model reads JSON text as SQLite does, also JSON5 (unquoted keys,
  hexadecimal numbers, trailing commas; owner decision 4). A BLOB argument, which SQLite
  reads as JSONB, is a model restriction.
- **Values.** A JSON scalar is an SQL value: an integer or a real as the JSON number
  text gives it, a string as text, `true` and `false` as 1 and 0, and `null` as NULL. An
  object or an array is JSON text. A path that selects nothing is NULL. Several paths
  give a JSON array of the selected values. `->` returns JSON text, and `->>` an SQL
  value; on their right, a bare label or an integer is a path (`'[5,6]' ->> 1` is 6).
  Of duplicate keys, the first one is selected.
- **JSON text.** Returned JSON text has no whitespace, keeps each number as written
  (`1.50`, `1e2`) and keeps each string escape as written (`["a\u0041"]` stays
  `["a\u0041"]`; checked through the library, because the sqlite3 shell converts
  `\uXXXX` in its input before SQLite reads it). The model must render
  JSON text exactly as SQLite does; its rules are part of this slice.
- **Errors.** Malformed JSON is `malformed JSON`, and a bad path is
  `bad JSON path: '%s'`, both reported while the statement runs.

### Further JSON functions (slice 6c)

- **Functions.** `json_type`, `json_valid`, `json_array_length` and `json` (owner
  decision 1), over the reading and the text rendering of slice 6b.

### `json_each` in FROM (slice 6d)

- **Form.** `json_each(json [, path])` as a source of `FROM`, alone, after tables in a
  comma list or an inner join. Its arguments may read the columns of earlier sources,
  so it is evaluated once for each row of those sources (SQLite's nested loop).
- **Rows.** One row for each element of the array or member of the object, in document
  order, with the columns `key`, `value`, `type`, `atom`, `fullkey` and `path`. A
  scalar JSON value gives one row.
- **Model.** The Queries level gets a source whose rows are a function of the earlier
  row. This is the first table-valued function; "Not decided here" lists them, and this
  amendment decides `json_each` only. `json_tree` and other table-valued functions stay
  refused.
- **Node positions.** The columns `id` and `parent` are SQLite's node positions (1, 4
  and 9 for `[10,{"x":1},30]`). The model computes them as SQLite does (owner decision 5);
  their rules are part of this slice.
- **Restrictions.** A `LEFT` or `RIGHT` join with `json_each` stays refused.

### The clock (slice 6e)

- **Input.** The recorder supplies one clock value to each statement and stores it
  (ADR 0005, section 3.2); within a statement, `now` does not change. The execution
  semantics takes the clock value of each statement as an input, and a migration must be
  correct for every clock value: the verification target quantifies over the clock value
  of each statement (owner decision 2).
- **Forms.** The keywords `CURRENT_TIME`, `CURRENT_DATE` and `CURRENT_TIMESTAMP`, and a
  `CURRENT_TIMESTAMP` default, which give the statement's clock value as text. The
  restriction `time-value` leaves the registry.
- **Defaults.** Column defaults come from draft #130, which slice 6e1 integrates first
  (owner decision 9); slice 6e2 adds the clock, the keywords and the default.

### Date and time functions (slice 6f)

- **Functions.** `date`, `time`, `datetime`, `julianday`, `unixepoch` and `strftime`
  with all of SQLite's formats (owner decision 3), over every time value that SQLite
  reads, `now` included. A time value that SQLite cannot read gives NULL.
- **Restrictions.** A modifier argument is a model restriction until slice 6g.

### Date and time modifiers (slice 6g)

- **Modifiers.** All of SQLite's modifiers (owner decision 3), with SQLite's
  normalization: `date('2024-01-31', '+1 month')` is `2024-03-02`. `localtime` and `utc`
  use the time zone of the execution profile, which the profile records; the recorder
  runs SQLite in UTC (owner decision 6).

### Order

6a first. 6c and 6d need the JSON reading of 6b. 6e changes the inputs of the execution
semantics and the verification target; 6f needs it for `now`, and 6g needs 6f. The JSON
slices and the time slices do not depend on each other, so their order may change.

### Testing

- **Cases.** Each rule above with native SQLite as the oracle: a query without `FROM`
  with and without a true `WHERE`, with aggregates, `ORDER BY` and `LIMIT`; each JSON
  value kind, missing paths, several paths, the operators, duplicate keys, JSON text
  rendering, JSON5 input, each further JSON function, and both errors; `json_each` over
  arrays, objects and scalars, alone and correlated with a table, with its node positions;
  each date function, modifier and format, `localtime` and `utc` in the profile's time
  zone, the clock in each function and keyword, and unreadable time values.
- **Mutants.** For each slice, one per rule that a wrong model could change, such as a
  query without `FROM` that returns no row, `true` returned as text, a number re-rendered
  in returned JSON text, `json_each` rows in key order, `now` read once per script, and a
  month added without SQLite's normalization.
- **Proofs.** Each write keeps `Conforms`; a statement without the new forms keeps its
  current semantics.

### Open questions

None; see "Owner decisions".

### Owner decisions

1. **JSON functions.** Decided on 2026-10-16: `json_extract`, `->`, `->>`, `json_type`,
   `json_valid`, `json_array_length` and `json` (slices 6b and 6c).
2. **Clock.** Decided on 2026-10-16: a migration must be correct for every clock value;
   the verification target quantifies over the clock value of each statement.
3. **Modifiers and formats.** Decided on 2026-10-16: all of SQLite's date and time
   modifiers and formats.
4. **JSON5 and JSONB.** Decided on 2026-10-16: the model reads JSON5 text; a BLOB
   argument (JSONB) is a model restriction.
5. **`json_each` node positions.** Decided on 2026-10-16: the model computes `id` and
   `parent` as SQLite does.
6. **Time zone.** Decided on 2026-10-16: the time zone is part of the execution profile;
   `localtime` and `utc` use it, and the recorder runs SQLite in UTC.
7. **Split.** Decided on 2026-10-16: the JSON work is three slices (6b reading and
   `json_extract`, 6c further functions, 6d `json_each`), and the time work three (6e the
   clock, 6f the functions, 6g the modifiers).
8. **Clock domain and form.** Decided on 2026-10-17: a migration must be correct for every
   64-bit clock value that SQLite's VFS can return, also where SQLite's date code fails;
   and the execution relation relates a script to the outcome of every assignment of clock
   values to its statements, so that the verification target quantifies over them without
   a change to `Contract.lean`.
9. **Defaults.** Decided on 2026-10-17: slice 6e models the `CURRENT_TIMESTAMP` default
   and so needs column defaults, which the model refuses today. It builds on draft #130
   (literal defaults for added columns and omitted `INSERT` values): slice 6e1 integrates
   #130 into this stack, and slice 6e2 adds the clock, the time keywords and the
   `CURRENT_TIMESTAMP` default.

## Amendment 6: Model structure after slices 1 to 6g (proposed)

Date: 2026-10-17. Status: PROPOSED.
Related: ADR 0006 (execution levels; the rule against catch-all arms); Amendment 5,
"The clock (slice 6e)" and owner decision 8; the refactor task
[20261017-model-structure-refactor](../plans/20261017-model-structure-refactor.task.md),
which makes the behaviour-preserving changes and depends on decision 1 below.

### Context

A review of the model on 2026-10-17, after slice 6g, found the code healthy and the
structure costly. The behaviour-preserving part of the remedy is a task, not a decision.
Two findings change what an ADR states, so they are decided here.

**Catch-all arms.** ADR 0006 requires that "every category and top-level domain/effect
match has explicit constructor cases; no catch-all forwards to another executor or
silently admits a new statement". The repository applies this to every match over a
project inductive. The effect after slices 1 to 6g: `Resolved.Statement` (13
constructors) has 13 full-list arms in 7 files that each encode one fact, whether a
statement is control, a definition, a write or a query; `Resolved.Expr` (14) has 11
hand-written traversals; `Syntax.Expr` (22) has "everything else" lists of 19 or 20
constructors in `Defaults`, `ReadDefaults`, `Context`, `SyntaxScope` and `Queries`. Adding
one constructor is a 10 to 16 file change, and most of those files only restate a
classification. The reason of ADR 0006 holds for semantic dispatch: in `step` and
`literalStep`, a new constructor must force a decision. It does not hold for a
classification that one function can make once and prove complete, as
`RestrictionKind.all` with `mem_all` already does for restrictions.

**The clock as a rewrite.** Slice 6e2 implements the clock by rewriting the resolved
statement before it runs: `Statement.atClock` replaces each time keyword by its text and
fills the cells of a `Statement.clocked` INSERT. That design needs an `atClock` and a
`readsClock` for every node type (`Expr`, `Arguments`, `Aggregate`, `Output`, `SortKey`,
`Query`, `ConflictClause`, `Statement`), a law for each, the carrier constructor
`Statement.clocked`, whose rows hold placeholder NULLs and which `step` and
`statementReady` do not accept, and the field `clock : Int` of `Resolved.Expr.date`, which
resolution sets to 0 and the execution overwrites. The concern spans 11 files. The
alternative is an evaluation parameter: `Expr.eval` and `step` take the statement's clock
value, and the resolved statement does not change between resolution and execution.
Owner decision 8 (the relation over clock assignments, `Contract.lean` unchanged) is not
affected by the choice.

### Decision 1: explicit arms for dispatch, classifiers for everything else

The rule of ADR 0006 is read as follows. A match that chooses a *semantic action* for a
constructor, in `step`, `literalStep`, `advance`, `Expr.eval` and the resolvers of each
statement, lists every constructor it handles explicitly and has no catch-all. A match
that only *classifies* constructors, to say "not mine", "has no expressions", "is a
write", "is a literal", uses one named classifier function per classification, whose
definition lists every constructor and whose docstring states the classification in plain
words. A new constructor then changes its semantic dispatch and each classifier, and the
compiler reports every one; the classification is not restated elsewhere. Catch-all
`_` arms over project inductives stay forbidden everywhere, so that adding a constructor
cannot pass unseen. The refactor task adds `Resolved.Statement.kind` under this reading.

### Decision 2: the clock as an evaluation parameter

Deferred to the owner; the alternatives are:

- **A. Keep the rewrite.** No change. Each new clock-reading form (a future `now`-like
  function, a `DEFAULT (datetime('now'))` once parenthesized defaults are modeled) adds
  its arm to the `atClock` and `readsClock` families and their laws.
- **B. Pass the clock.** `Expr.eval (clock : Int) (row)`, `Query.run`, `step` and
  `literalStep` take the statement's clock value; `runSqlAt` passes `clock position` to
  each step. `Statement.clocked`, `ClockCell`, `ClockRows`, `ClockRowRules`, the
  `atClock` and `readsClock` families and `StatementClockLaws` are removed. Resolution of a
  `VALUES` item or an omitted default that reads the clock keeps the expression in the
  row instead of a value (rows become `List Expr`, or a value-or-expression cell type).
  `runSqlAt_of_readsClock` becomes "a script with no clock-reading expression gives the
  same outcome for every clock", proved once over the evaluator instead of per node type.
  Cost: `Resolved.Statement.insert` and `upsert` change their row type, so the codec, the
  conformance `Outputs`, `Preservation` and `UpsertConforms` proofs and the example proofs
  change; about 20 files. No corpus verdict changes.

The recommendation is B, in its own task after the refactor task, because the refactor
reduces the number of files that B touches. If the owner chooses A, the refactor task's
item 2 still applies to `StatementClock`.

### Not decided here

- Folding `Resolved.Statement.insert` into `upsert` with no clauses and an all-ABORT
  policy, which would remove one execution path and one preservation proof.
- Splitting `Resolution/` into the shared IR types, the resolver and its proofs as three
  directories, which changes every import line and is a mechanical follow-up once the
  task is done.

### Owner decisions

1. **Classifiers.** Proposed 2026-10-17 (decision 1 above); awaiting the owner.
2. **Clock parameter.** Proposed 2026-10-17 (decision 2, alternative B); awaiting the owner.
