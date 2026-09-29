# ADR-0004 evidence review status

Created 2026-09-29. Status: ACTIVE.
Task: [evidence review corrections](20260929-adr4-evidence-review.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Current state

Review findings verified against generator, native recorder/replay, upstream proxy and measurement code. Previous W1–W7 reports remain historical; this follow-up strengthens their evidential scope. Work remains in the dedicated adr4 workspace, unmerged pending owner approval.

## Progress

- Task and validation outcomes recorded before implementation. Archive provenance verified against the prior user instruction supplying ~/Downloads/sqlite-docsrc.tar; no new download required.
- Native replay now rejects missing/merged/extra statement observations as harness errors while preserving legitimate first-error truncation. Both native paths retain SQLITE_TOOBIG and SQLITE_MISMATCH as SQL outcomes. DQS CREATE INDEX on an unknown quoted key is rejected on both pinned engines. Validation: record and DQS suites, 7 passed (0.91s).
- Generator now varies all five affinities with admitted values, changes UPDATE values, and adds to populated rows. Every generated run retains native conversion probes with MODEL_UNSUPPORTED outcomes. Fixed seed 4004 (20 examples, 8 steps) produced 88 agreements and 44 unsupported probes. Actual isolated production mutants were killed: UPDATE 7 cases, ADD padding 16, rollback 7, uniqueness 20. Targeted generation/record/upstream tests: 22 passed in 25.96s. Evidence: reports/20260929-adr4-generator-{review,mutations}.json. No production model changes.
- Corpus diagnostics preserve raw verdicts and separately classify trailing read-only observations: on unchanged v2, 4 cases are blocked only by queries, 41 still have unsupported prefixes, and 130 have other blockers. Same-file close/reopen is a real native boundary with rollback of pending writes; profile-compatible db_config calls replay. Source-line EVIDENCE-OF contexts replace file-wide attribution; ambiguous blocks remain uncredited. ATTACH and nondeterministic functions are excluded before side effects, and every mined candidate must repeat exactly. A randomblob WAL case exposed this additional replay gap during refresh. Record/DQS/upstream checks: 13 passed in 6.08s, including actual reopen/rollback and the DQS index-schema path.
- Native gcov counters now reset before and dump/reset after each migration statement; final observation/connection cleanup is discarded before exit. Instrumented and ordinary traces/verdicts agree for 101 cases. Measured 4,707/14,023 native branch arcs in reached functions; model 36/41 scoped arms. The report asserts sqlite3_open, sqlite3_close and fixture binding functions never enter the measured counters. Historical coverage including harness queries is not comparable to this migration-only denominator.
- Strengthened statement alignment also checks native consumed-byte boundaries, including truncated error traces. Matching native/parser syntax errors from e_select remain explicit frontend exclusions; corrupt or failed parser transport does not. Query-only cases now have their own category: all four previously agreeing empty prefixes in v2 are QUERY_ONLY_CASE, not DDL progress. The same distinction applies to 42 empty prefixes in v3. Full `just test` passed: 56 model, 12 Atuin, 13 CLI, 19 kernel, plus 264 host tests and 28 subtests. Source/dependency checks: 54 passed. Full-suite model output: /nix/store/0kxryqd6mxawyk8an6l993kdxg6gp8rk-sqlite-verifier-test-model-1.
