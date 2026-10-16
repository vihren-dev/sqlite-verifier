# Queries without FROM, slice 6a of ADR 0012: status

Created 2026-10-16. Status: DONE.
Task: [20261016-select-without-from.task.md](20261016-select-without-from.task.md).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), Amendment 5, "Queries
without FROM (slice 6a)".

## Relevant files

- Frontend: `belay/sqlite/syntax_select.py`.
- Resolution: `packages/belay-sqlite/Belay/Sqlite/Resolution/Queries.lean`,
  `Resolution/Sources.lean`, `Resolution/Syntax.lean`.
- Queries: `Resolution/QueryForm.lean`, `QueryJoins.lean`, `QueryJoinLaws.lean`,
  `QueryEval.lean`.
- Conformance: `packages/verifier-conformance/VerifierConformance/Outputs.lean`.

## Progress

- 2026-10-16: task and status files, stacked on #141 (Amendment 5). Native facts checked on
  SQLite 3.51.0: `count(*) WHERE 0` is one row 0; `SELECT *` is `no tables specified`;
  `a` and `t.a` are `no such column`; `GROUP BY 1` is one row.

- 2026-10-16: implementation. Frontend: `syntax_select.select` gives a null source and
  no joins without FROM. `Syntax.Statement.select` and `Resolved.Query.table` are
  optional; `resolveTables` gives no table and the empty scope; `Query.source` gives one
  row with no cells (`Query.source_none`); `*` with the empty scope is the new prepare
  error `noTablesSpecified`. Examples in `QueryResolutionExamples.lean`. 22 authored cases
  (`conformance/authored_fromless.py`, all AGREE), 4 mutants (`fromless_mutants.py`, in the
  queries measurement: 80 s locally), the corpus 21 writer. Tests that used `SELECT 1;` as
  unsupported SQL use `SELECT DISTINCT 1;`.

- 2026-10-16: the slice commit went in before `test-full` passed (my error); its checks
  then failed in two tests: the profile test still used `SELECT 1;` as unsupported SQL,
  and one more legacy authored case now agrees (22 instead of 21). Fixed in a refactor
  commit, with the review finding on the semantic-subset wording (a false `WHERE` keeps
  no source row, but `count(*) WHERE 0` is one row). `test-full` passes.

- 2026-10-16: CI time (local, `--check` rebuilds, base vs branch): harness 22/21 s,
  mutants 276/275 s, model 241/240 s, frozen 137/138 s. Pull request A opened as #142.
- 2026-10-16: pull request B: corpus 21 (22 cases, all AGREE) is claimed, and the 7
  upstream cases that now agree join `mustAgree` (v3 59 to 60, v4 27 to 28, v5 481 to
  486). New judge lock. Slice 6a is DONE; slice 6b (JSON reading and `json_extract`)
  follows.
