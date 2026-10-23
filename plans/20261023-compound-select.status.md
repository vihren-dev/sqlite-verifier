# Status: compound SELECT (ADR 0019, slice 3)

Created 2026-10-23. Status: IN PROGRESS (the run, the resolution and the frontend of a compound,
the authored corpus, the mutants and the surface fixture are in; the judge change is next).
Task file: [task](20261023-compound-select.task.md).
Specification: [ADR 0019](../docs/adr-0019-guide-sql.md), D3 and D7.

## Progress

- 2026-10-23: the task file, from the code after ADR 0017's S3, native probes with the dev
  shell's `sqlite3` 3.51.0 (one statement for each line), SQLite's `select.c`, `resolve.c`,
  `expr.c` and `parse.y` of 3.51.0 (`sqlite-conformance-upstream-3.51.0` in the Nix store), and
  `experiments/model-gaps/next_groups.py` over the Nix verdict after slice 1.
- 2026-10-23: review round 1 (three musts) fixed with native probes: the 32-bit rule for an
  `ORDER BY` column number, no collation for a scalar subquery, and the point where SQLite reads
  `LIMIT` and `OFFSET` for each operator (task file, outcomes 7, 9 and 10).
- 2026-10-23: review round 2 (three musts) fixed with native probes: the exact integers that
  name a column (not `-2147483648`), the read point of `LIMIT` in mixed chains (a `UNION ALL`
  gives it to its left operand), and text that converts to an integer (`LIMIT ?` bound to `'1'`).
- 2026-10-23: owner decisions 1 and 2: the lead proceeds on the recommendation (the owner accepted
  both later the same day, see "Owner decisions"). ADR 0019 D3 is
  amended with the rules of `IN` and scalar subqueries over a compound, the `ORDER BY COLLATE`
  rewrite, and a compound statement in a trigger body outside slice 3.
- 2026-10-23: review of the ADR amendment (one must) fixed with native probes: after the
  `ORDER BY COLLATE` rewrite, `IN` and a scalar subquery read the column of the derived table
  (ADR 0019 D3, task file outcome 9); slice 3 refuses them with a restriction.
- 2026-10-23: review round 2 of the amendment (one must) fixed: after the rewrite, a scalar
  subquery reads only the affinity of the derived table's column, and no collation.
- 2026-10-23: the run of a resolved compound (`Resolved.Compound`, `CompoundRows.lean`,
  `CompoundRun.lean`): the four operators, the duplicate rule, the kept row, and the points where
  SQLite runs a term and reads the window, with the examples of outcomes 1 to 3, 8 and 10
  (`CompoundExamples.lean`, `CompoundFailureExamples.lean`). Resolution and the frontend do not
  give a compound yet.
- 2026-10-23: review of the run (two musts) fixed: examples of `statementReady` for a compound,
  and the laws of a query without a fallible call move to `QueryPlainLaws.lean`.
- 2026-10-23: resolution and frontend of a compound: `Syntax.Compound` (`SyntaxSubquery.lean`), the
  terms as subqueries whose parent is the compound's query, the order of table lookups and name
  errors (`CompoundTerms.lean`), the compound `ORDER BY` (`CompoundOrderBy.lean`), the columns and
  the shape (`CompoundResolution.lean`), the names of the derived table after the `ORDER BY
  COLLATE` rewrite (`CompoundNames.lean`), the restrictions `compound-subquery-column` and `compound-order-by-term`, and the
  frontend (`Translation/CompoundSelect.lean`) with the errors of outcome 6. Examples:
  `CompoundResolutionExamples.lean`; tests: `tests/syntax_compound_test.py` and the compound paths
  of `tests/surface/TranslationChecks.lean`.
- 2026-10-23: review of the resolution and frontend (two musts) fixed with native probes: SQLite
  names the derived table's columns before it resolves the names, so `likely(a)` keeps its text
  and `A` its spelling; `docs/semantic-subset.md` states the rule of the derived names.
- 2026-10-23: the authored corpus of compound SELECT (`conformance/authored_compound.py`,
  `authored_compound_subqueries.py`, written as corpus version 49 by `compound_evidence.py`): the
  cases of the task's "Tests" list, each with a kernel proof in
  `tests/conformance_query_coverage_test.py`; eight mutants (`compound_mutants.py`), each with a
  target case; and `Empty` of an `EXCEPT` query in `tests/surface/GuideQueries.lean`. Limits of
  the recorder (`native_ordering.query_groups`): a statement orders by a number or a name of the
  first term, under the first term's collation; a subquery has no `LIMIT`; and no case has a term
  failure that a `LIMIT` prevents, because the recorder runs the statement again without its
  `LIMIT`. `LIMIT 'x'` is out of the model's scope also for one SELECT, so the corpus has no case
  of it. Tests: `tests/conformance_query_coverage_test.py`, `tests/conformance_corpus_writers_test.py`,
  `tests/conformance_query_mutants_test.py -k compound`, `tests/mutant_guards_test.py` and
  `tests/surface_guide_test.py`.
- 2026-10-23: review of the corpus (one should) fixed: the status line and "Remaining" give the
  done work and the next steps.

## Owner decisions

On 2026-10-23, the owner accepted the recommendation of decisions 1 and 2: amend D3 with SQLite's
rules of `IN` and a scalar subquery over a compound and of the `ORDER BY COLLATE` rewrite, and keep
a compound statement in a trigger body out of slice 3. ADR 0019 D3 has the amendments of both
(2026-10-23).

1. **D3 and the columns of a compound.** D3 says that each column compares under the collation of
   a compound column (the left-most `SELECT` whose column has one). This is true for the
   duplicate rule and for an `ORDER BY` term without `COLLATE`. Two rules of SQLite differ, and an
   implementer acts on them:
   - `x IN (q)` over a compound reads the affinity and the collation of the right-most term's
     column, and a scalar `(q)` only its affinity (a subquery has no collation), not the compound
     collation (task file, outcome 9; `'A' IN (SELECT n FROM t UNION SELECT m FROM u WHERE 0)` is
     0 for a `NOCASE` column `n` with `'a'` and a `BINARY` column `m`).
   - When an operator is not `UNION ALL` and an `ORDER BY` term has `COLLATE`, a term without
     `COLLATE` sorts under the collation of the left-most term's expression, not the compound
     collation (outcome 7, `convertCompoundSelectToSubquery`).
   Recommendation: amend D3 with both rules, as the repository follows native SQLite. The task
   file already states them.
2. **A compound as a statement of a trigger body.** D3 says that a compound may be a statement.
   The task file keeps a compound `SELECT` statement in a trigger body refused by the frontend
   (`Translation/Triggers.lean`); a compound subquery inside a trigger body's statement is in
   scope. A lexical count over the out-of-scope cases after slice 1 finds at most 11 cases of v5
   and 11 of v4 with a compound in a trigger. Recommendation: keep it out of slice 3, and say so in
   the amendment of D3; add it when a measurement or a guide example needs it.

## Notes for later slices

- **Slice 5 (D4)** makes a compound the source of `INSERT`. `valueRows`
  (`Translation/Writes.lean`) keeps its refusal until then.
- **Slice 4 (D5)** reads a compound as a derived table, a view or a common table expression.
  Such a source column has other rules (`sqlite3SubqueryColumnTypes`): the collation of the
  left-most term's expression only, and an affinity from the types of the terms. Native, over
  `t(n TEXT COLLATE NOCASE)` with `'B'` and `'a'`: `SELECT 'b' AS x UNION ALL SELECT n FROM t ORDER
  BY x` gives `'a'`, `'b'`, `'B'`, and `SELECT x FROM (SELECT 'b' AS x UNION ALL SELECT n FROM t)
  ORDER BY x` gives `'B'`, `'a'`, `'b'` (`BINARY`).

## Measurement

Over the Nix verdict after slice 1 (2026-10-23): 274 of 1,881 out-of-scope cases of v5 and 36 of
624 of v4 have a compound mark; with compound `SELECT`, 228 more cases of v5 and 18 of v4 have no
mark left. These are upper bounds. Log: `build/agent-logs/adr19s3-next-groups.json` (local).

## Files

- Model: `Resolution/Syntax.lean`, `Resolution/SyntaxSubquery.lean`, `Resolution/CompoundTerms.lean`,
  `Resolution/CompoundOrderBy.lean`, `Resolution/CompoundNames.lean`,
  `Resolution/CompoundResolution.lean`, `Resolution/SyntaxExpr.lean`, `Codec/SyntaxJson.lean`,
  `Resolution/QueryForm.lean`, `Resolution/Queries.lean`, `Resolution/QueryTerms.lean`,
  `Resolution/Collations.lean`, `Resolution/SubqueryShapes.lean`,
  `Resolution/SubqueryResolution.lean`, `Resolution/SelectResolution.lean`, `QueryResults.lean`,
  `QueryRun.lean`, `QueryWindow.lean`, `Subqueries.lean`, `PossibleResults.lean`,
  `StatementOutput.lean`, `StatementStep.lean`, `StatementClock.lean`, `SqlLaws.lean`.
- Frontend: `Translation/Select.lean`, `Translation/CompoundSelect.lean`, `Translation/Subqueries.lean`,
  `Translation/Statements.lean`, `Translation/Triggers.lean`.
- Conformance: `conformance/authored_queries.py` (`QueryCase`), `authored_evidence.py`,
  `parameter_evidence.py` (the model of a writer), `parameter_mutants.py`, `resolve_mutants.py`,
  `native_ordering.py` and `query_window.py` (the limits of the recorder).
- Corpus: `conformance/authored_compound.py`, `authored_compound_subqueries.py`,
  `compound_evidence.py`, `compound_mutants.py`; `tests/surface/GuideQueries.lean`.

## Tests for each commit

The tests that touch the commit, then `just review`: the frontend tests
(`tests/syntax_queries_test.py` and the new compound tests), `tests/conformance_model_test.py`,
`tests/conformance_pipeline_test.py`, and for the corpus `tests/conformance_query_coverage_test.py`
and `tests/conformance_corpus_writers_test.py`; `just dev-build` and `just dev-verdict` for each
edit of `packages/`.

## Remaining

- The judge change: corpus version 49 recorded by `conformance/compound_evidence.py`, its claim,
  the newly agreeing cases in `mustAgree`, and `integrity/judge.lock.json` (owner's approval).
- `just test-full` and `just verdict` at the end of the slice; `just test-nix` and
  `just test-scheduled` before the pull requests; the judge change and the work as two pull
  requests.
