# ADR 0005: reference-workload conformance corpus

Created 2026-09-30. Status: DONE, verified 2026-10-05.
Status: [progress](20260930-adr5-reference-corpus.status.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).
Completion: [source-bound core gates](../reports/20261005-adr5-review-gates.json).
The separately owner-authorized [review repair](20261002-adr5-review-remediation.task.md)
supersedes the original v4 default with v5; original v4 outcomes remain fulfilled.
The workload-suite gate is verified complete in its owning repository.

## Observable outcomes

The core provides the C0–C7 tooling: typed parameters, result shapes and rows,
SQLite-compatible ordering and tie cuts, direct DML counts, verified execution
profiles and deterministic native clocks, faithful upstream extraction, bounded
snapshot-sharing shards, authored boundary/requirement cases, a frozen v4 corpus,
and bounded development replay plus complete progress reports. Frozen v1–v3
artifacts remain unchanged and readable. Unsupported model behavior never agrees.

An external workload can use the same recorder, replay and progress commands.
The workload suite is complete only with its full statement/migration inventory,
verified profile, frozen shard digest, and combined generic/workload baseline.
Workload-specific SQL, names, profiles, cases and results stay outside the core.
Model extension and C8 production-semantic mutants are subsequent work.

## Verification

Each package has its own task/status record and bounded behavioral tests.
Core acceptance includes native recording/replay, compiled Lean classification,
negative comparator cases, profile/manifest mismatch rejection, extraction
fidelity checks, native replay of all frozen v4 records, size budgets, and a
development replay sample within 60 seconds. Relevant cached Nix test targets,
host tests, source-boundary checks and Markdown link checks must pass.
The real-workload gate requires real inputs and native evidence in the private
product repository; a synthetic workload proves only the core mechanism.

## Constraints and relevant sources

Reuse `StructuralCodec.lean` and `migration_check/structural.py` from ADR 0003 P3.
`VerifierConformance/Case.lean` remains the comparison authority. Native evidence
is translator-independent in `conformance/native_record.py`; the current adapter
is `conformance/native_replay.py`. `conformance/upstream_pilot.py` and its Tcl
proxy own extraction; `conformance/corpus.py` and `progress.py` own replay/reporting.
Keep native truths immutable, preserve parameter positions and storage classes,
use bags rather than sets, and never acquire supplementary evidence by repeating
a write. A build/profile mismatch is a harness error, not a model result.
