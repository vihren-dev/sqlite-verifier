# Frozen corpus progress and coverage

Created 2026-09-29. Status: DONE.
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Required outcomes

A versioned frozen corpus reports AGREE, DISAGREE and MODEL_UNSUPPORTED counts by requirement ID and upstream test area, alongside separately reported harness errors. Regenerate the 3.51.0 requirement list. Report measured model constructor/error/match-arm and native gcov branch coverage; denominators remain tied to source/corpus identities.

## Observable validation

Repeat replay on a fixed corpus gives stable counts; corpus changes require a new version; coverage reflects actual execution and explicit denominators, never inferred universal refinement. Instrumented native execution produces a real gcov report.

## Constraints and relevant code

conformance/coverage_catalog.py, coverage_evidence.py and W6 corpus. Coverage builds remain separate from the product engine. Unsupported-to-agreement transitions must not hide new disagreements.

Work stays in the dedicated adr4 workspace. No merge to main or adr3 rebase before user approval.
