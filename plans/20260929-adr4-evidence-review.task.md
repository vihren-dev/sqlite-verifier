# ADR-0004 evidence review corrections

Created 2026-09-29. Status: ACTIVE.
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Required outcomes

Generated evidence varies affinities, changes UPDATE values, adds columns to populated tables, and retains unsupported outcomes. Fixed-seed generated cases detect production-model mutants for ignored UPDATE values, missing ADD padding, ineffective rollback, and disabled uniqueness checks. Historical agreement totals remain historical.

Corpus reporting distinguishes migrations blocked only by trailing read-only observations. Upstream capture preserves same-file close/reopen state and credits cases with their applicable EVIDENCE-OF references. A new immutable corpus adds public e_*.test evidence and authored affinity, transaction and index scenarios; existing corpus versions remain unchanged.

Statement alignment failures are harness errors. Native semantic errors survive recording. Native coverage measures migration execution separately from fixture/observation queries. Both engine profiles test unsupported DQS fallback in CREATE INDEX. Reports state denominators, surviving limitations, source identities and archive provenance.

## Observable validation

Bounded model tests cover the changed behaviors and actual mutation kills; native replay verifies newly frozen evidence. Fixed-seed generation, corpus progress and migration-only coverage produce reviewable reports. Relevant Nix targets and the full test suite pass before completion. No main merge or adr3 rebase occurs.

## Constraints and source references

Reuse conformance/state_machine.py, native_record.py, native_replay.py, upstream_proxy.tcl, upstream_pilot.py, progress.py and measure_coverage.py. SQLite stops at the first SQL error, so a shorter reached trace is not by itself a splitter mismatch. Reopening rolls back an open transaction and resets connection settings. Read-only PRAGMAs must be distinguished from settings changes. Requirement tags describe scenarios, not proof of entire requirements. Production model semantics and frozen native observations must not be changed to manufacture agreement.
