# Frozen corpus progress and coverage: status

Created 2026-09-29. Status: DONE.
Task: [Frozen corpus progress and coverage](20260929-adr4-w7-progress.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

The user supplied the missing release-tagged docsrc archive. SQLite's own tools
regenerated 3,500 requirements; every full ID passes an independent MD5 check.
The 164-row working matrix retains zero-test requirements and separates upstream
Tcl citations from our executed evidence. V2 preserves all 177 v1 records exactly
and adds six authored requirement scenarios: 8 AGREE, 175 MODEL_UNSUPPORTED,
0 DISAGREE, 0 HARNESS_ERROR. Parser transport failures remain harness errors.

Separate source-instrumented Lean and Clang/gcov SQLite builds execute 93 admitted
cases with the same verdicts and observations as the ordinary builds. Measured:
7/7 statement constructors, 7/8 errors, 36/41 scoped explicit match arms;
6,003/16,272 native branch arcs in reached functions, including setup/observation
SQL. Reports contain source/corpus digests, tool version and exact exclusions.
See [progress documentation](../docs/conformance-progress.md),
[progress report](../reports/20260929-adr4-corpus-v2-progress.json), and
[coverage report](../reports/20260929-adr4-coverage.json).

Focused progress/native recorder checks: 7 passed in 1.97s. Documentation,
upstream fixture, instrumented model and native builds all succeeded. Final validation: `just test` passed (264 host tests plus 28 subtests; Nix targets:
12 Atuin, 13 CLI, 19 kernel and 48 model tests). The final model rerun passed all
48 tests in 47.17s. Source/dependency identity checks passed 54 tests; after the
baseline-report input addition, all 17 dependency tests passed again.
All 534 docsrc source files match the release manifest.
[Completion report](../reports/20260929-adr4-completion.json). No merge or adr3 rebase
is authorized; all changes remain in the dedicated workspace.
