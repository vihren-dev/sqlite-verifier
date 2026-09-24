# Bounded conformance coverage report

Created: 2026-09-24. Status: DONE.
Parent: [Step 1](20260924-step-1-schema-extensions.task.md).
Specification: engineering brief, Conformance and coverage infrastructure and CI.

The shared local/CI checks must produce a machine-readable report separating
named proof checks, grammar inventory/regressions, documented claim traceability,
upstream fixture import, semantic support, and native/model observations. Every
count must name its denominator and exclusions. Missing/failed evidence must not
be reported as zero discrepancies or proof acceptance. Imported upstream fixtures
must retain their unsupported dependency and unproved model status.

Observable checks cover report structure, evidence failures, denominator wording,
and a real report using the pinned parser, SQLite, and Lean. Reporting does not
claim native refinement, full corpus execution, statement/production execution
coverage, or real-pilot acceptance. Reuse the existing evidence runners and exact
upstream identifiers; do not create a second fixture or proof implementation.

The standalone report, documented scope, real pinned evidence run, and bounded
report regressions are complete and independently reviewed. Shared command/CI
wiring is coordinated separately with the technical lead.
