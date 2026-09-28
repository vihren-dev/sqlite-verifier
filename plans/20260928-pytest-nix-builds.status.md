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

Final native CI for the integrated Linux package fix and expanded source set;
native benchmark pilot and complete measurement matrix; measured rollout decision
and final independent requirement-by-requirement review.
No end-to-end performance claim yet.

- Complete integrated Darwin `just check` passes at `079c252c`: run
  `bfb63b9e-a685-47cf-b07a-10b544b306d7` contains exactly 285 fresh source cases
  plus 64 validated cached unit cases, all phases passing, and current complete
  `EVIDENCE_CHECKS_PASSED` coverage. CI exposed a second host issue: prepending the
  bundled Lean bin directory also selected its clang instead of the Nix compiler.
  The reviewed fix leaves PATH unchanged and selects Lean/Lake explicitly; both
  smoke cases pass with ambient Lean absent. Together with portable host hashing,
  26 integrated driver/fingerprint cases pass. Native CI must rerun these fixes.
- Final review also identified nested detached process groups escaping an outer
  helper timeout. A focused cleanup regression/fix is in progress. Standalone
  Nix input-identity checks are being made independently discoverable and part of
  native CI; case-order and benchmark acceptance remain open.

- Integrated the reviewed 42-case Nix input-identity conversion: real offline
  evaluations cover selected inputs, required names, ignored generated trees and
  documentation in ordinary native CI. The 397-case inventory preserves all 244
  legacy mappings. Its focused 44-case Darwin check passes in 29.86s. The new
  suite has an explicit 150-second limit; existing deadlines are unchanged.
- Backported the reproduced macOS sandbox fixture correction to build-output
  PR 3: select the pinned bare Python executable rather than its pytest wrapper.
  The legacy fixture fails with the wrapper (exit 255) and passes with the bare
  interpreter, including isolation and timeout assertions; production policy is
  unchanged. PR 4 already has the same fixture correction. Both draft PRs are
  running native CI again; no performance experiment has been dispatched.

- Integrated reviewed nested-timeout cleanup `b9437177`: stop and discover owned
  descendants across sessions, kill them, reap the direct child and bound diagnostic
  draining. Production sandbox limits are unchanged. Thirty-three focused checks
  plus two subtests pass; four new cases pass alone/reversed, and the old helper
  fails the negative control. The 401-case collection/inventory now matches the
  integrated tree exactly, retaining 244 immutable legacy mappings.
- CLI 19 passes reversed (108.65s pytest) and every case alone. The installed Atuin
  13 passes reversed after a real offline reinstall (166.20s including setup),
  and each passes alone through that installed root with poisoned ambient imports.
- Native experimental run 36398817022 passes the complete macOS graph, source,
  archive and installed gates. Linux passes the Nix graph and all fresh source
  evidence, then correctly rejects export of an unsigned project Lean derivation.
  Its absolute ELF references must be relocated within the copied payload before
  dependency collection; signature verification remains mandatory. This packaging
  correction and both-platform revalidation remain in progress.

- Removed the obsolete parser script runner after a complete caller search. Both
  independently collected native reuse cases remain; seven focused checks and
  nineteen subtests pass. The inventory's parser implementation hash will be
  refreshed with the final packaging changes; preserved legacy source evidence
  is unchanged. A fresh reverse-order run of all 395 source cases is in progress.

- PR 3 passed all three required checks and merged as `0055011aa7da581eff0b1afe7e57fbd95152a082`.
  PR 4 now targets main. Integrated the reviewed Linux staged-ELF correction;
  sixteen focused checks pass in 0.20s, signature enforcement remains unchanged,
  and the 409-case catalogue reconciles exactly (403 source; 19 installed).
- All 395 source cases from checkpoint `092412ca` pass together in reverse order
  in 327.20s with 166 subtests. Same-run receipt aggregation produces complete
  fresh coverage. New eight packaging cases are undergoing independent/reverse
  selection checks; 139 additional resource-free cases already pass individually.
  The remaining source resource cases are being checked individually.
- Benchmark scheduling now allows twelve independent native jobs concurrently,
  with unchanged sample workloads and sixty-sample acceptance; GitHub may queue
  macOS jobs at the account limit. Pilot and measurements are still pending.

- Selection-isolation audit is complete: exact sets of all 403 source cases and
  all 19 installed cases have passing standalone and reverse-order receipts,
  including every setup/call/teardown phase. Root native-reuse cases, six installed
  package cases, and eight added relocation cases also pass separately. The member
  [audit status](20260928-selection-isolation.status.md) links the evidence.
- Final integrated pure-unit Nix output rebuild succeeds: 64 cases and 62 subtests
  pass in 0.64s at
  `/nix/store/3gbm3vfmgzn6a2wjb214yx7wk5rgkyf6-sqlite-verifier-unit-checks-1`.
  Native run 36406499807 tests implementation `ffc49c06` on both platforms; its
  outcome remains pending. No performance rollout is enabled.
