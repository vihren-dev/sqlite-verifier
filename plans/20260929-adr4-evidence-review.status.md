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
