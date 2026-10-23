# Compound SELECT (ADR 0019, slice 3)

Created 2026-10-23. Status: DONE (2026-10-23; pull requests #229 and #230). The owner accepted
the decisions in the [status file](20261023-compound-select.status.md). Specification: [ADR
0019](../docs/adr-0019-guide-sql.md), D3, and the order of D7 (amended 2026-10-22): before ADR
0017's S4, which needs `EXCEPT`. Related: [ADR 0018](../docs/adr-0018-surface-sql.md) D1
(subqueries), D3 (`DISTINCT`, amended 2026-10-21) and D6 (the results that SQLite may give).

## Process

As for slice 1: local jj commits with the tests that touch each one; at the end of the slice the
local verdict, the authored corpus with kernel proofs and mutants, and `just test-full`. Then two
pull requests, which wait for the owner (ADR 0019, owner decision 3; `AGENTS.md`, "Development
claims"): the judge change, with the new authored corpus, its claim, the newly agreeing cases in
`mustAgree` and `integrity/judge.lock.json`, which needs the owner's approval; and the work.

## Scope

The slice covers a compound `SELECT` as a statement and as a subquery (`EXISTS`, `IN`, a scalar
subquery) in every place where the model accepts a subquery today. It does not cover these forms,
and the frontend keeps its refusals: a compound as the source of `INSERT` (D4, slice 5); a compound
in `FROM`, in a view or in `WITH` (D5, slice 4); a `VALUES` term (`VALUES (1), (2) UNION SELECT 3`);
`NULLS FIRST` and `NULLS LAST`; a compound statement in a trigger body (status file, decision 2).

## Outcome

Each fact below was checked natively with the dev shell's `sqlite3` 3.51.0 and SQLite's `select.c`,
`resolve.c`, `expr.c` and `parse.y` of 3.51.0. In the examples, `t(a TEXT, n TEXT COLLATE NOCASE)`
holds `('1', 'a')` and `u(b INTEGER, m TEXT)` holds `(1, 'A')`.

1. **Operators and order.** `UNION ALL`, `UNION`, `INTERSECT` and `EXCEPT` have equal precedence and
   apply from left to right: `SELECT 1 UNION SELECT 2 INTERSECT SELECT 2` gives `2`. `UNION ALL`
   gives the left rows, then the right rows. `UNION` gives the distinct rows of both. `INTERSECT`
   gives the distinct left rows that equal a right row. `EXCEPT` gives the distinct left rows that
   equal no right row. Each term is a `SELECT` that the model resolves today, with its own joins,
   `WHERE`, `GROUP BY`, `HAVING`, `DISTINCT` and aggregates.
2. **Equal rows.** Two rows are equal when each column compares equal under the compound column's
   collation, without affinity: NULL equals NULL (`SELECT NULL EXCEPT SELECT NULL` gives no row,
   `SELECT 1, NULL INTERSECT SELECT 1, NULL` one row), `1` equals `1.0`, and `1` differs from `'1'`
   (`SELECT 1 INTERSECT SELECT '1'` gives no row). The collation of column i is that of the
   left-most term whose expression i has a collation in the sense of `sqlite3ExprCollSeq`
   (`multiSelectCollSeq`): a `COLLATE` in the expression, or a column reference, also under unary
   plus and `CAST`, with its declared collation, `BINARY` when it declares none. Without a
   `COLLATE`, a literal, a function call, `||` and a scalar subquery have none. With no term that
   has one, `BINARY`. So `SELECT m FROM u EXCEPT SELECT n FROM t` gives `'A'` (`m` gives `BINARY`),
   `SELECT 'A' UNION SELECT n FROM t` gives one row (`NOCASE` from `n`), and `SELECT max(n) FROM t
   UNION SELECT 'A'` gives two rows.
3. **The kept row.** When a set of equal rows holds rows that differ (`'a'` and `'A'` under
   `NOCASE`, `1` and `1.0`), SQLite's plan chooses the row that `UNION`, `INTERSECT` or `EXCEPT`
   keeps: without `ORDER BY` the last that it reads (`SELECT 1 UNION SELECT 1.0` gives `1.0`,
   `SELECT 1.0 UNION SELECT 1` gives `1`), with `ORDER BY` the merge of the sorted terms. Then the
   model does not describe the statement, as for `DISTINCT`. `INTERSECT` and `EXCEPT` keep rows of
   their left result only, so for them only equal left rows that differ matter; which left rows they
   keep does not depend on the plan.
4. **Columns.** The result columns have the names of the left-most term (`SELECT 1 AS one UNION
   SELECT 2 AS two` names its column `one`), except after the rewrite of outcome 7: then they
   have the names of the derived table's columns (`sqlite3ColumnsFromExprList`), which SQLite
   gives before it resolves the names: the `AS` alias, else for a name or `x.c` under `COLLATE`
   that name as written (`A` for a column `a`), else the text (`likely(a)`), and the column
   names of `*`; `true` and `false` become `columnN`; and a name
   that is taken gets the suffix `:1` to `:4`, after which SQLite adds a random number (a
   restriction). `SELECT a COLLATE NOCASE FROM t EXCEPT SELECT a FROM u ORDER BY 1 COLLATE
   BINARY` names its column `a`; without `COLLATE BINARY`, `a COLLATE NOCASE`. All terms have the same number of columns, else
   SQLite's prepare error `SELECTs to the left and right of UNION ALL do not have the same number of
   result columns`, with the operator between the two terms.
5. **The order of prepare errors.** SQLite finds the tables of every term, and expands `*`, before
   it resolves a name. It then resolves the terms from right to left; it checks the column count of
   a term and the term on its right after the names of that term; and it resolves the compound's
   `ORDER BY` last. So `SELECT 1 FROM missing UNION SELECT nosuch FROM t` gives `no such table:
   missing`, `SELECT nosuch1 UNION SELECT nosuch2` gives `no such column: nosuch2`, `SELECT nosuch1
   UNION SELECT 1, 2` gives `no such column: nosuch1`, `SELECT nosuch UNION SELECT 1 UNION SELECT 1,
   2` gives the count error, and `SELECT 1 UNION SELECT 1, 2 ORDER BY 5` too. Where the model cannot
   give SQLite's order, it gives a restriction, as slice 1 did with `parameter-error-order`.
6. **Errors of the parser.** SQLite's parser actions (`parserDoubleLinkSelect`) give `ORDER BY
   clause should come after UNION not before` and `LIMIT clause should come after UNION not before`,
   with the operator to the right of the right-most term that has the clause, and `too many terms in
   compound SELECT` above 500 terms (the profile's `compoundSelect`; 500 terms are accepted). The
   last message wins (`sqlite3ErrorMsg` replaces it): `SELECT 1 ORDER BY 1` and 500 times `UNION
   SELECT 1` gives the second. The frontend refuses these scripts with `INPUT_ERROR` and SQLite's
   message.
7. **`ORDER BY` of a compound.** Each term names a result column, else a prepare error. An integer
   literal from 0 to 2147483647, also in hexadecimal, in parentheses and under unary `+` and `-`
   (`sqlite3ExprIsInteger`: `0x1`, `(1)`, `-1`, `- -1`), is a column number; outside 1 to N it is
   `1st ORDER BY term out of range - should be between 1 and N`. Other integers (`2147483648`,
   `-2147483648`, `0x80000000`) and any other term are tried on each term from the left: first as an
   `AS` alias of that term (the case of letters does not matter), then as an expression equal to a
   result expression of that term. `SELECT 1 AS a UNION SELECT 2 AS b ORDER BY b` and `SELECT a FROM
   t UNION SELECT lower(a) FROM t ORDER BY lower(a)` are valid. Else `1st ORDER BY term does not
   match any column in the result set`: `ORDER BY a + 1`, `ORDER BY 1 + 0`, `ORDER BY 1.0`, `ORDER
   BY '1'` and `ORDER BY ?`, which sorts by a value in a single `SELECT` (slice 1). The match
   ignores a `COLLATE` of the term; the sort uses it. A term without `COLLATE` sorts under the
   compound column's collation (outcome 2), with one exception: when an operator of the compound is
   not `UNION ALL` and a term has a `COLLATE`, SQLite sorts the compound as `SELECT * FROM
   (compound)` (`convertCompoundSelectToSubquery`), and a term without `COLLATE` sorts under the
   collation of the left-most term's expression, `BINARY` when it has none. Over `w(n TEXT COLLATE
   NOCASE)` with `'C'` and `'a'`, `SELECT 'b' AS x, 1 AS y UNION SELECT n, 1 FROM w ORDER BY y
   COLLATE BINARY, x` gives `'C'`, `'a'`, `'b'`; without `COLLATE BINARY`, and with `UNION ALL`, it
   gives `'a'`, `'b'`, `'C'`. Duplicates stay those of outcome 2.
8. **`LIMIT` and `OFFSET`** apply to the whole compound, as to a single `SELECT`: literals and lone
   parameters, `datatype mismatch` for `LIMIT ?` bound to `'x'` when it runs (a literal `LIMIT 'x'`
   is the restriction `window-value`, as for one `SELECT`), no limit for a negative `LIMIT`,
   and the restriction `negative-offset` for a literal negative `OFFSET`. Without `ORDER BY` the row
   order is SQLite's plan (`UNION ALL`: left, then right; the others: the order of a temporary
   index), which the harness compares as a multiset; with a `LIMIT` and no `ORDER BY` every row
   ties, so the possible results (ADR 0018 D6, `Output.oneOf`) are each choice of rows.
9. **Compound subqueries.** `EXISTS (q)`, `x IN (q)` and `(q)` take a compound. A name in a term
   resolves in that term, then in the queries around the compound, never in another term. `x IN (q)`
   reads the affinity and the collation of the right-most term's column, and a scalar `(q)` only its
   affinity (`x.pSelect` is the right-most term in `exprINAffinity`, `sqlite3CodeRhsOfIN` and
   `sqlite3ExprAffinity`; `sqlite3ExprCollSeq` gives a subquery no collation), not the compound
   collation: `'1' IN (SELECT b FROM u UNION SELECT 5)` is 0, `'1' IN (SELECT 5 UNION SELECT b FROM
   u)` is 1, `'A' IN (SELECT n FROM t UNION SELECT m FROM u WHERE 0)` is 0, `'A' IN (SELECT m FROM u
   WHERE 0 UNION SELECT n FROM t)` is 1, `(SELECT b FROM u UNION SELECT 5) = '1'` is 0, and `(SELECT
   m FROM u WHERE 0 UNION SELECT n FROM t) = 'A'` is 0. When outcome 7 sorts the compound as
   `SELECT * FROM (compound)`, `x IN (q)` reads the column of that subquery instead: the collation
   of the left-most term's expression and the affinity of `sqlite3SubqueryColumnTypes`
   (`'A' IN (SELECT 'a' COLLATE NOCASE UNION SELECT 'b' WHERE 0 ORDER BY 1 COLLATE BINARY)` is 1);
   a scalar `(q)` reads only that affinity and has no collation (`(SELECT 'a' COLLATE NOCASE
   UNION SELECT 'b' WHERE 0 ORDER BY 1 COLLATE BINARY) = 'A'` is 0).
   The model refuses such an `IN` or scalar subquery with a new restriction, which has an example in
   `conformance/restriction_examples.py`; slice 4 adds it with the columns of a derived table.
   `EXISTS (q)` reads no column and takes it. Two columns where one is needed give
   `sub-select returns 2 columns - expected 1`. A scalar subquery reads its first row only when
   every permitted order gives the same first value (ADR 0018 slice 1): `(SELECT 2 UNION SELECT 1
   ORDER BY 1 DESC)` is 2, and `(SELECT 2 UNION SELECT 1)` is not described.
10. **When SQLite runs a term.** Without `ORDER BY` (`multiSelect`), SQLite runs the terms from left
    to right, each to its end, but not the right term of `EXCEPT` or `INTERSECT` when the left
    result is empty (`SELECT 1 INTERSECT SELECT 2 INTERSECT SELECT abs(-9223372036854775808)` gives
    no error), and `UNION ALL` stops when its `LIMIT` is full (`SELECT 1 UNION ALL SELECT
    abs(-9223372036854775808) LIMIT 1` gives `1`; with `UNION` it fails). SQLite reads `LIMIT` and
    `OFFSET` (`computeLimitRegisters`) before the first term when the compound has `ORDER BY`. Else
    the last operator decides, but a `UNION ALL` gives them to its left operand, the compound of the
    terms on its left: before the first term when each operator is `UNION ALL`, before the right
    term of `INTERSECT`, and after both operands of `UNION` and `EXCEPT`. Terms after the read do
    not run for `LIMIT 0`, and a value that is not an integer (`LIMIT ?` bound to `'x'` or `1.5`;
    `'1'` is 1) fails at the read. So `SELECT 1 INTERSECT SELECT abs(-9223372036854775808) LIMIT 0`
    gives no error, and with `UNION`, or as `SELECT abs(-9223372036854775808) UNION SELECT 1 UNION
    ALL SELECT 2 LIMIT 0`, it fails. With `ORDER BY` (`multiSelectOrderBy`) SQLite merges the sorted
    terms and can stop before it reads every row of a term: over `p(a INTEGER PRIMARY KEY)` with 1,
    2 and 3, `SELECT 1 INTERSECT SELECT a FROM p WHERE CASE WHEN a = 3 THEN
    abs(-9223372036854775808) ELSE 1 END ORDER BY 1` gives `1`, and the same without `ORDER BY`
    fails. A failure is certain in the model only where SQLite runs it in each plan; else it is
    `may`, and the statement is not described.

## Measurement

Over the Nix verdict after slice 1, `experiments/model-gaps/next_groups.py` finds 228 more
out-of-scope cases of v5 and 18 of v4 with no mark when compound `SELECT` is in scope (upper bound).

## Tests

- Lean examples of each outcome, with kernel proofs (`decide +kernel`): each operator, the
  precedence example, the NULL and `1.0` examples, each source of a compound collation, the kept row
  that differs, each prepare error of outcomes 4, 5 and 7, the `COLLATE` exception of outcome 7, a
  window, and each probe of outcomes 9 and 10.
- Frontend tests: each operator, the spans, and the errors of outcome 6, also with 501 terms.
- An authored corpus (`conformance/authored_compound.py` and its evidence writer, which joins
  `tests/conformance_corpus_writers_test.py`), each case with a kernel proof in the coverage set
  (`tests/conformance_query_coverage_test.py`), recorded as the next corpus version (49, unless
  slice 2 records its corpus first): each operator as a statement, chains with mixed operators,
  NULLs, the collation sources of outcome 2, `EXCEPT` and `INTERSECT` under a collation, `ORDER BY`
  by number and by a name of the first term, and by an alias of a later term and by an expression in
  scalar subqueries, `LIMIT` with and without `ORDER BY`, each prepare error of outcomes 4, 5 and 7,
  compound subqueries in each form of outcome 9 with correlation, the failures of outcome 10 that
  SQLite skips and that it gives, and the guide's form `SELECT ... EXCEPT SELECT ...` that compares
  two tables.
- The verdict of every corpus: cases that newly agree and none that leave AGREE.
- Mutants (`conformance/compound_mutants.py`), each killed by an authored case: right-to-left
  evaluation; `EXCEPT` that keeps duplicates of its left rows; the compound collation from the
  right-most term or always `BINARY`; `IN` with the compound collation instead of the right-most
  term's; NULL unequal to NULL in the duplicate rule; the right term of `EXCEPT` run when the left
  result is empty; an `ORDER BY` term sorted under `BINARY` instead of the compound collation.
- A surface fixture (`tests/surface/`): `Empty` of an `EXCEPT` query over one database by `decide`.

## Key points

These notes describe the code before the slice (2026-10-23); the status file names the files
that the slice adds.

- **The syntax holds one `SELECT`.** `Syntax.Statement.select` (`Resolution/Syntax.lean`) and
  `Syntax.Subquery` (`Resolution/SyntaxExpr.lean`) are flat, with the child numbers 0 to 10
  (`Resolution/Queries.lean`, `Translation/Subqueries.lean`). The JSON of an existing statement must
  not change: a new field of `select` goes into `Syntax.Statement.defaultFields`
  (`Codec/SyntaxJson.lean`), and `Syntax.Subquery` has derived instances that write every field.
- **A query that holds queries.** `Resolved.Query` (`Resolution/QueryForm.lean`) is one `SELECT`,
  and `Resolved.Statement.query` holds the query and the subqueries. A `Query` with a list of
  `Query` terms is a nested inductive type; ADR 0018 D1 named subqueries by index to keep the types
  apart and the kernel's reduction structural. The terms meet the same tension. A term's subqueries
  name their parent through `Subquery.parent`, where `none` is the statement's query.
- **What exists to reuse.** The duplicate rule of `DISTINCT` (`sameOutput`, `uniqueRecords` and
  `distinctCertain` in `QueryResults.lean`, which keeps the first row). `resultCollations`
  (`Resolution/Collations.lean`) gives `BINARY` for an expression without a collation, so the
  compound rule needs the optional form (`explicitCollation <|> columnCollation`). `SubqueryShape`
  (`Resolution/SubqueryShapes.lean`) holds the first column of the one `SELECT` (affinity,
  collations, the lowest cell read), and `inCollation` combines them.
- **`ORDER BY` of one `SELECT`** (`namedResult`, `aliasIndex`, `integerLiteral` in
  `Resolution/QueryTerms.lean`) takes a parameter as a value and an expression over the source row;
  outcome 7 differs. `SortKey.output` names a result column.
- **Readers of `Query`.** `bindWindow` (`QueryWindow.lean`), `Query.run` (`QueryRun.lean`),
  `windowCertain` and `subqueryRun` (`Subqueries.lean`), `possibleResults` and its laws
  (`PossibleResults.lean`, `PossibleResultsLaws.lean`), `StatementOutput.lean`, `resultNames`
  (`OutputTable.lean`), `readsOnly` (`QueryOutputs.lean`; the surface's `Script.isQuery` uses it),
  `returnsRows`, `possibleOutput`, `StatementClock.lean`, `StatementStep.lean` and `NoWrites`.
- **The frontend.** `queryClausesWith` (`Translation/Select.lean`) requires one `oneselect`, and
  `lift` (`Translation/Subqueries.lean`) lists subqueries in text order. The action-free grammar
  puts `ORDER BY` and `LIMIT` on the last `oneselect` and accepts them on earlier ones, so outcome 6
  is frontend work. Mutants of `belay-sqlite-text` are not measured (`resolve_mutants.py`).
- **The native recorder.** `query_groups` (`conformance/native_ordering.py`) ranks the rows with
  `SELECT q.*, dense_rank() OVER (ORDER BY keys) FROM (compound) AS q`. A derived table's column has
  the collation of the left-most term only (`sqlite3SubqueryColumnTypes`), so a case whose compound
  collation comes from a later term and whose order the recorder observes fails to record (checked).
  `projected_order` (`query_window.py`) maps keys by the result names only, so a statement that
  sorts by an alias of a later term or by an expression is not recorded, nor is a nested `LIMIT`.
  The authored cases avoid these forms; a change of the recorder is a judge change.
- **Text that calls a compound unmodeled.** `tests/conformance_pipeline_test.py`,
  `tests/conformance_model_test.py`, `tests/syntax_queries_test.py`, maybe
  `tests/conformance_profile_test.py` (the 3.46.0 pin), `docs/semantic-subset.md` and the docstring
  of `Translation/Select.lean` use or list it as refused SQL.
