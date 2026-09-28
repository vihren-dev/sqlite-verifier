# ADR 0001 implementation status

Created: 2026-09-28. Status: IN PROGRESS.

Task: [observable requirements](20260928-pytest-nix-builds.task.md).
Specification: [accepted ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md).
Baseline: `4df62fa7`, with unchanged runtime from `7a99c71f` (v0.1.1).
Relevant sources: `justfile`, `tests/`, `conformance/coverage_report.py`,
`nix/flake.nix`, `packaging/`, `tools/run_independent_suites.py`, `.github/workflows/ci.yml`.

## Progress and evidence

- Accepted the ADR and recorded the complete acceptance scope before coding.
  Existing source still uses script/unittest runners and dependency-only caching.
  Disk check: 41 GiB free; no cleanup needed. The unrelated uncommitted ADR 0002
  draft remains in the primary workspace and is excluded from implementation
  workspaces and commits. Preparation documentation links checked separately.

- Development interpreter now includes pinned pytest 9.1.1; the archive builder
  requires an explicit bare pinned Python path passed by `just runtime-package`.
  Verified that the bare interpreter cannot import pytest, archive CLI describes
  the required option, and focused resource/loader/module-deletion tests pass.
  Nix environment still has exactly two files; one persistent shell is used.
- Added the pytest catalogue, per-case runtime fixtures, bounded process runner
  and separate source/installed phase reports. Fourteen real subprocess regressions
  pass in 4.97s, covering absent tools during collection, bad metadata, setup and
  teardown errors, malformed JSON, timeout cleanup and artifact separation.
  Independent review caught and fixed installed Lean fallback to host tools;
  a regression proves missing bundled Lean fails despite an available host compiler.
  Harness checks are fresh integration evidence, excluded from pure-unit caching.
  Existing suites are being converted separately; full discovery parity is pending.
- Integrated independently reviewed Nix toolchain/parser/Lean/runtime targets and
  explicit-root packaging. Darwin Nix sandbox builds and input-identity mutation
  tests passed; real Linux execution remains pending. Nine merged staging/CI-scope
  checks pass. The Atuin run exposed read-only store modes copied into fixtures;
  `copy_mutable_tree` now makes only private copies writable, retaining executable
  bits. A regression passes both case orders and proves original bytes unchanged.
- Converted all nineteen CLI scenarios to independent pytest cases with private
  example copies and explicit baseline setup. The reviewed suite passes against
  the immutable Nix runtime in 114.58s; independent/reversed runs remain pending.
  Compilation and baseline conversions are independently reviewed on their member
  branch: all 24 pass together, reversed and one at a time. Integration is pending.
- Integrated the reviewed Atuin, remaining script conversions, compilation/baseline
  cases, cache fingerprints and explicit 64-case pure-unit Nix target. The member
  records retain the exact validation commands and results; Linux, full source and
  installed acceptance remain pending. Equivalent inventory branch versions were
  reconciled using the latest compilation/baseline inventory, preserving all rows.
- Archive staging, Nix export, signature verification and compression succeeded
  against the immutable Darwin runtime. Installed acceptance exposed a real macOS
  sandbox bug: ASCII JSON Unicode escapes did not identify Unicode filesystem
  paths in SBPL (14 failures, five passes). A minimal copied-executable experiment
  isolated the cause. The reviewed fix emits UTF-8 path literals with the same
  escaping and permissions; all eight sandbox checks pass in 0.85s, including
  quoted Unicode executable paths and preserved read/write/network restrictions.
  A rebuilt runtime/archive and fresh installed acceptance remain required.
- Rebuilt the runtime after the Unicode fix; the real offline archive installation
  and all nineteen installed cases pass in 170.12s, including all thirteen Atuin
  cases under poisoned ambient imports. Archive signature verification passed.
- Integrated fresh receipt aggregation: all 95 producer cases pass in 35.04s,
  then `coverage.json` reports `EVIDENCE_CHECKS_PASSED` from that same run without
  launching producers again. Removed legacy aggregate wrappers. Twenty-three
  negative/completeness checks plus nine subtests pass; independent review approved
  the denominator, freshness and error-reporting changes.
- Moved pytest registration to root `conftest.py` so repeated catalogue output
  works when the output file already exists. Its Nix/cache/scope inputs are explicit;
  collection now finds exactly 355 cases. Sixty-four focused integration/metadata
  checks pass with 35 subtests; the descendant-process cleanup check separately
  passes in the approved host shell (the ordinary tool sandbox forbids `ps`).
- The integrated pure-unit derivation passes 64 cases and 62 subtests in 0.72s.
  Reviewed CI transport remains opt-in; the benchmark workflow has a four-job pilot
  and the complete 60-sample matrix. No remote native CI or benchmark run has yet
  been dispatched. Whole-source integration and measurement gates remain open.
- Published two stacked draft review units: [build outputs and packaging, PR 3](https://github.com/vihren-dev/sqlite-verifier/pull/3)
  and [pytest/CI integration, PR 4](https://github.com/vihren-dev/sqlite-verifier/pull/4).
  Native CI is now running. The experimental Linux job found host Python 3.10
  lacks `hashlib.file_digest` before entering Nix; the integration member is
  replacing that helper with a portable streaming SHA-256 loop. The macOS
  complete local source run remains in progress; benchmark runs have not started.

## Remaining implementation

Whole-source command validation and case-order checks; both-platform source and
installed acceptance; native benchmark pilot and complete measurement matrix;
rollout decision and final independent requirement-by-requirement review.
No end-to-end performance claim yet.
