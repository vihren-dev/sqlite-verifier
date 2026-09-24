# Bounded coverage reporting status

Created: 2026-09-24. Status: DONE.
Task: [coverage reporting](20260924-coverage-report.task.md).
References: engineering brief §Conformance and coverage infrastructure;
`docs/sqlite-parser.md`, `docs/conformance-fixtures.md`, `docs/conformance-model.md`.

Existing evidence has separate denominators: 409 generated default grammar
productions (no production execution instrumentation), 20 parser smoke scripts,
3 selected upstream assertion instances of 59 textual sites / 2 IDs of 55,
and 5 explicitly derived model/native comparisons. Documentation maps three
upstream requirement IDs and two snapshot anchors; that bounded map is not a
complete inventory of SQLite documentation claims. Six named theorem probes
will be reported as a declared audit scope, not all library theorems.

The report runs bounded evidence commands and preserves failure diagnostics.
The technical lead owns shared justfile/workflow integration. No production
code or evidence expectations are changed.

## Checked implementation

Implemented the declared inventory and bounded evidence shell in
`conformance/coverage_catalog.py`, `coverage_evidence.py`, and `coverage_report.py`;
usage and exclusions are in `docs/coverage.md`. The JSON retains separate checks,
raw native observations, exact named theorem axiom output, import counts, and
unknown counts on failed comparisons. Incomplete or invalid exit-zero runner
output fails instead of claiming no discrepancies. Source/fixture inventory
errors still emit a failed report. No original fixture or formal theorem changed.

`timeout 15s python3 tests/coverage_test.py` passes five tests in 1.011s, covering
failed/unavailable/timed-out evidence, malformed/incomplete reports, and explicit
denominators. `compileall` succeeds for all four authored Python modules.
The real report command with pinned Nix SQLite passes under a 300s outer timeout:
409 generated / 409 upstream default productions, 20 smoke scripts, six named
proof/axiom probes, three selected upstream assertions, and five derived
native/model comparisons. The latter alone report zero observed discrepancies.
The upstream cases remain NOT_YET_MODEL_CHECKED and production execution
coverage remains NOT_INSTRUMENTED. Report artifact: ignored `build/coverage.json`.

Coordinator review accepted the scope and requested exact case identity checks.
Those checks now require unique complete derived case names and upstream
(id, occurrence) identities, plus production grammar/translation statuses. A
mocked duplicate-success regression verifies failed reports retain unknown
comparison/discrepancy counts; the real report still passes. Coordinator
independently reviewed the corrected sources and reproduced all five bounded
tests under Nix (1.011s), then accepted this component. Technical lead owns the
shared justfile/CI hook and report artifact retention. Component DONE; this is
not Step 1 acceptance.
