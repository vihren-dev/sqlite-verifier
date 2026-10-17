# JSON reading and json_extract, slice 6b of ADR 0012: status

Created 2026-10-16. Status: DONE.
Task: [20261016-json-extract.task.md](20261016-json-extract.task.md).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), Amendment 5, "JSON reading
and `json_extract` (slice 6b)".

## Relevant files

- Frontend: `belay/sqlite/syntax_expressions.py`, `belay/sqlite/syntax_queries.py`.
- Resolution: `packages/belay-sqlite/Belay/Sqlite/Resolution/QueryExprs.lean`,
  `Resolution/QueryForm.lean`.
- Evaluation: `QueryEval.lean`, `NumberConvert.lean`.
- Conformance: `packages/verifier-conformance/VerifierConformance/Outputs.lean`.

## Progress

- 2026-10-16: task and status files, stacked on #143 (slice 6a, PR B). Native facts
  checked on SQLite 3.51.0, one statement per line: whitespace and comments are
  removed; `é` is decoded and `\n` and `\"` stay escaped; JSON5 numbers are
  normalized (`0x1F` 31, `.5` 0.5, `Infinity` 9e999, `NaN` null); an integer beyond 64
  bits and `1E400` are REAL (`Inf`); `$[-1]` is a bad path and `$[#-1]` the last element;
  `json_extract` with one argument is NULL; INTEGER and REAL arguments are read as text.

- 2026-10-16: native facts on evaluation: short-circuits, `X AND 0` folding, `LIMIT` and
  deferred result columns under `ORDER BY` decide whether an error occurs; recorded in
  the task's key points.

- 2026-10-16: design. The JSON reading, paths, values and rendering are ported from
  SQLite's `json.c` into `Belay/Sqlite/Json/` (in progress). `->` and `->>` are calls
  of the functions `->` and `->>`, as SQLite's parser makes them, so the syntax does not
  change. `Resolved.Expr` gets a JSON call over a mutual argument list (`Arguments`): a
  nested `List Expr` loses derived `DecidableEq`, and a mutual type keeps it and
  structural recursion that the kernel reduces (checked). Evaluation is one evaluator in
  `Except`, and `eval` is derived from it. A JSON error is part of the outcome only where
  SQLite certainly evaluates the call (see the task's key points); any other possible
  error makes the statement unsupported for that data.

- 2026-10-16: native facts on failure sites (one statement per line): a constant
  `WHERE` term is evaluated once before the rows, also over an empty table (`DELETE` and
  `UPDATE` too); a result column over an empty table is not; an aggregate query over no
  row evaluates its scalar columns over NULL cells; `ON` constants are evaluated over an
  empty join; an aggregate operand fails also under `OFFSET 1`, a scalar column does not;
  `X AND 0` in `WHERE` evaluates `X`; `RETURNING` of `INSERT` is evaluated.

- 2026-10-16: model. `Json/` holds the port of SQLite's `json.c` (reader, paths, values,
  rendering; 381 calls differentially checked against native SQLite, and the examples in
  `ScalarExamples.lean` and `PathExamples.lean`); `Json/JsonApply.lean` dispatches the
  three functions. `JsonFaults.lean` defines `mayFail` and `mustFail`; `JsonReady.lean`
  adds the JSON checks to `statementReady`: a query is ready when no call may fail or the
  failure is certain (only without `FROM`); a write is ready when no call of its `WHERE`
  and `SET` values may fail, also over the empty row, and its `RETURNING`, and every
  `ON CONFLICT` clause, has no JSON call. `step` fails a query with
  `ExecutionError.functionError` (code 1, step phase), whose outputs are the names and
  no rows. A constant `VALUES` item or `SET` value whose JSON call may fail is the new
  restriction `constant-function-error`. `NoWrites` now also excludes queries with a JSON
  call. Authored cases `conformance/authored_json.py` (21, all AGREE), mutants
  `conformance/json_mutants.py` (8), corpus writer `conformance/json_evidence.py`
  (corpus 22). The pinned documentation has no `json1.html`, so the cases name the
  extract-operator requirements of `lang_expr.html`. Deviation from the task: a write
  never reports a JSON error (it is unsupported for that data instead), because the
  model does not describe when SQLite evaluates constants in writes.

- 2026-10-17: review findings (two catch-all matches over project types) fixed in a
  refactor commit; its review was clean. CI time (local, `--check` rebuilds, base vs
  branch): harness 23/22 s, mutants 215/251 s, model 223/229 s, frozen 138/140 s. The
  mutant growth is the 8 JSON mutants (about 22 s; each rebuilds most of the model) and
  a slower rebuild of the larger model in every mutant test; the measurements run one
  after another, so moving the JSON mutants does not change the total. Pull request A
  opened as #144.
- 2026-10-17: pull request B: corpus 22 (21 cases, all AGREE) is claimed, and the 45
  upstream JSON cases that now agree join `mustAgree` (v5 486 to 531). New judge lock.
  Slice 6b is DONE; slice 6c (`json_type`, `json_valid`, `json_array_length`, `json`)
  follows.
