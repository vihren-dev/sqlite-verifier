# Queries without FROM, slice 6a of ADR 0012

Created 2026-10-16. Status: open.
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), "Amendment 5: Functions and
queries without FROM (slices 6a to 6g)", "Queries without FROM (slice 6a)", with the owner
decisions of 2026-10-16 (#141). Related: slices 6b to 6g follow and use this form for
their cases.

## Pull requests

- **Pull request A (subject):** frontend translation, resolution, query evaluation,
  proofs, examples, authored coverage cases, mutants and a corpus writer. No change under
  `judge/` or `integrity/`.
- **Pull request B (judge, owner approval):** the coverage corpus (version 21) is frozen
  and claimed, and cases that newly agree are added to `mustAgree`.

## Outcome

1. **Form.** `SELECT result-columns [WHERE condition] [GROUP BY terms] [ORDER BY terms]
   [LIMIT ...]` without `FROM` is admitted, also inside a migration and as the query of a
   case. The forms of a query with `FROM` that the model refuses stay refused.
2. **Source.** The source is one row with no columns. The query returns that row, or no
   row when the `WHERE` condition is not true (false or NULL). Aggregates read the rows
   that pass `WHERE`: `SELECT count(*)` is 1 and `SELECT count(*) WHERE 0` is 0.
   `GROUP BY` gives one group for the one row. `ORDER BY`, `LIMIT` and `OFFSET` apply as
   for any query.
3. **Names.** A column name is `no such column: %s` (a qualified name `t.a` also; SQLite
   does not say `no such table`). `*` is SQLite's prepare error `no tables specified`.
4. **Values.** The expressions of today, and the `integer overflow` and other rules of
   slice 2, apply unchanged (`SELECT 9223372036854775807 + 1` is a REAL).
5. **Verification target.** `Contract.lean` does not change; a query without `FROM`
   changes nothing, so every statement keeps `Conforms`.
6. **Evidence.** Authored coverage cases agree with native SQLite 3.51.0 and have kernel
   proofs; each mutant below changes a verdict; the verdict counts of the claimed corpora
   do not go down.

## Tests

- Lean examples: a query without `FROM` with a true, false and NULL `WHERE`; `count(*)`
  with and without rows; `GROUP BY`; `ORDER BY` and `LIMIT`; the two prepare errors.
- Proofs: a query without `FROM` keeps `Conforms`; the laws of queries over a source
  hold for the one empty row.
- Authored coverage cases (native SQLite as the oracle): each item of the outcome,
  arithmetic, comparisons, `CAST` and `COALESCE` without `FROM`, `integer overflow` of
  `SUM`, and a migration with a query without `FROM` between writes.
- Mutants, each changing the verdict of an authored case: no row instead of one row; a
  false `WHERE` that still returns the row; `count(*)` over zero rows giving no row; `*`
  accepted.
- Frontend tests: the translated form, and that `SELECT` without `FROM` with `HAVING`,
  `DISTINCT` or a window still refuses as today.

## Key points for the implementer

- **Frontend.** `belay/sqlite/syntax_select.py` refuses the form ("A SELECT without FROM
  is not modeled"). `Syntax.Statement.select` takes a `TableReference`; an optional
  source decodes JSON `null` as none, so stored JSON with a source stays valid.
- **Resolution.** `Resolution/Queries.lean` (`resolveSelect`) and `Resolution/Sources.lean`
  build the scope from the sources; a query without `FROM` has the empty scope, which
  already exists for `VALUES` items (`Scope` with no sources).
- **Queries level.** `Resolved.Query.table : Nat` (`Resolution/QueryForm.lean`) names the
  first source; `Query.source` (`QueryJoins.lean`) and its law (`QueryJoinLaws.lean`)
  read it. The conformance layer (`VerifierConformance/Outputs.lean`) reads query
  sources too.
- **Upstream evidence.** Many upstream cases (`expr`, `func*`, `json101`, `e_select`) use
  this form; the verdict counts show which now agree and which need slices 6b to 6g.
- **Kernel and mutant cost.** Keep authored cases small; CI's `test-full` is close to its
  limit, so measure the mutant and model suites after the change.
