# Shared table shape implementation status

Created 2026-10-06. Status: IN PROGRESS. Resumed 2026-10-09 after T10 delivery.
Task: [observable outcomes](20261006-shared-table-shape.task.md).
Sources: public issue #15 and approved product T07 outcome.

## Current state

T10 is delivered. The resumed implementation starts from accepted main
`c0dfbac0`, through PR #77, in the `shared-table-shape` Jujutsu workspace.
The original paused changes remain under `archive/paused-t07-20261009`.

The model now stores columns and retained properties in `TableShape`.
`Table` and `TableSchema` share that representation. The codec retains the flat
version-one transport. Application proofs, generated terms, conformance and
Atuin callers have been adapted to the current package boundary.
The standalone model, full runtime, conformance runtime and checked public
documentation build successfully on macOS. Test acceptance is still in progress.
The dated progress entries below retain the original paused work's history.

## Source audit

The current `Table` and `TableSchema` each store columns and properties. Current
`Conforms` compares columns and separately requires a property equality for each
stored table. The required shape equality retains those obligations together.
Derived lookups, empty database construction, column append, literals, SQL
admission and projections all use the duplicated fields today.

The existing structural JSON format is flat and is frozen into native and model
fixtures. Explicit codecs can preserve that one transport while constructing
the nested Lean representation. Python structural records need no new version
or fallback. Generated Lean schema terms and all source fixtures must migrate.
Fresh regression terms come from the current decoder; retained historical Lean
reports are evidence rather than an alternate implementation.

Relevant files and acceptance are recorded in the task. Root's reviewed T15
application-key helper/variant tip is needed for final all-caller assembly.
API-reference coverage derives the actual compiled imports and needs the checked
new source tip before final coverage. Neither coordination requires changing the
approved model package name or the existing verification vocabulary.

## Progress

- 2026-10-06: Read current public issue #15 and its empty comment list, and the
  approved T07 card. Audited model structures, conformance, schema/projection
  proofs, frontend emitters, shared structural codecs, frozen structural cases
  and current bundle regression tests. Recorded observable outcomes and bounded
  acceptance before feature work. Recorded the then-authorized sequence; the latest owner review below
  supersedes that sequence and requires T10 first. Reported source/caller scope to root and API worker.

- 2026-10-06: Assembled named reviewed T15 `731f03c8` and API-reference
  guide/inventory `f8f42bbf` dependencies with the prepared task. Source files
  merged without conflicts. Resolved the journal alone, preserving every raw
  parent line, multiplicity and parent order, plus the exact pending T05/T15/API
  review rows. All 25 public-library and structural-codec base modules compiled
  sequentially through the existing pinned Lean runtime in 12.95 seconds, with
  a 30-second bound per compiler. The local log is `build/t07-base-compile.log`.
  No Nix build, native replay or timing acceptance ran.

- 2026-10-06: Partial shared-shape migration now owns columns/properties in
  `TableShape`, compares whole shapes in `Conforms`, keeps the existing flat
  transport through explicit codecs, and migrates library, T15 helper, generated
  input and Atuin callers. All 30 public/codec/conformance modules compiled in
  18.70 seconds; after the final codec correction, 29 reachable codec/conformance
  modules compiled in 17.08 seconds. Each compiler has a 30-second bound; no new
  forbidden axiom appears. Local log: `build/t07-compile.log`.
- 2026-10-06: Initial short-test runs exposed mistakes in the new compiler/golden
  fixtures and two missing unused prerequisite links in the private test wrapper.
  These were source-owned fixture errors, corrected before the latest owner hold.
  The terminal run passed all nine shape, codec-golden, retired-field,
  application-key and trace/output compiler checks in 5.58 seconds, with 10/15/30
  second per-command bounds. XML: `build/t07-shape-compiler.xml`. The wrapper uses
  the current compiled source library and existing pinned tools; it is not a
  rebuilt or installed runtime acceptance. One automatic approval timed out;
  the permitted single retry of the shortened test command succeeded.
- 2026-10-06: The already-started fresh Atuin compiler pass completed at the hold:
  14 actual generated-input, approved and candidate proof modules compiled in
  9.93 seconds, each bounded at 30 seconds. Log: `build/t07-atuin-compile.log`.
  The mandatory approved `SchemaBinding.lean` caller changed, but its proposed
  baseline hash has not been updated or approved. Invoice baselines and every
  T03/T02/T05 archived receipt remain unchanged. The current Atuin baseline is
  therefore stale for this partial source and cannot supply runtime acceptance.
- 2026-10-06: Latest owner review requires T10 first and explicitly requests an
  incomplete checkpoint. Stopped T07 edits and new checks, retained the existing
  partial source and exact pending base-review row on its own named branch, and
  marked this task PAUSED. Feature independent review has not run. The inherited
  mutation harness still has the T05 removed-docstring boundary failure; its T07
  metadata access change does not fix that failure. T05 now owns that correction.

## Open gates

Source and native suite acceptance, complete model acceptance on both platforms,
offline installed acceptance on both platforms, independent feature review and
final R8 owner review remain open. This task is not DONE.

## Resumed checkpoint, 2026-10-09

The owner confirmed T10 completion and requested continued implementation.
PR #56 is merged as `39040632`, and main records T10 as DONE. Preserved the
original paused checkout under `archive/paused-t07-20261009` and the exact
`49c100e5` feature diff against `e884e1d8`. Started a fresh change in the existing
shared-table-shape workspace on accepted main `c0dfbac0` through PR #77.
The partial code still needs migration to the independent model package and
current frontend; no resumed build or test pass is claimed. Historical entries
above describe the original paused work and its older rules.

Decisions waiting for the owner:

- Final model and codec review after the resumed implementation passes checks.

Progress on 2026-10-09: Ported the shared shape structures, execution and
preservation modules to the accepted model package. Adapted structural lookup
facts and the flat version-one codec. The old application-only types remain
outside the model package. The first compiler pass found a damaged declaration during the port. Restored
the retained declarations, adapted application callers and generated terms,
and completed the compiler checks recorded above.

Validation on 2026-10-09: The pinned macOS builds passed for the standalone
model and codec, full runtime, conformance runtime and public documentation.
The documentation inventory checked all 244 authored declarations, with no
missing or ordinary docstrings. The source suite passed 460 tests and 57
subtests. Twenty focused shape, caller and frontend checks passed. A further
14 checks passed after adding missing-metadata decoder cases.

The first native Atuin run detected the changed SchemaBinding fixture's stale
checksum. Updated only that file's entry in the fixture manifest. The next
native run passed all 12 Atuin tests, 28 kernel tests and 56 model tests.
Bundle acceptance passed all 73 tests, and CLI acceptance passed all 16 tests.
The exact final model test source passed all 56 sandbox tests. The remaining macOS sandbox suites also passed: frozen 146, harness 129,
sample 22 and upstream 117. All nine native suites passed, with 599 tests
in total. The final model run includes the added missing-metadata cases.
Logs remain local under `build/20261009-t07-resume`; no validation result
folder is committed. Linux and installed-runtime acceptance remain open.

The resumed model, codec and caller migration is ready for a source commit and
independent review. This is a checked implementation checkpoint, not final
two-platform or installed acceptance. The remaining gates above still apply.

Independent review of `97ad82aa` found one model docstring that used
application approval wording. Replaced it with “additional invariants.” The
review also marked the codec and whole-shape conformance for final owner review;
both gates remain open under the existing implementation authorization.

The docstring correction compiled successfully. The checked public inventory
still covers all 244 authored declarations. The correction and review outcomes
are committed as `7454f437`. Its independent review found no further issues.

Linux acceptance started from the exact tracked source of `7454f437` in
`/var/tmp/sqlite-verifier-t07.zse20W/source` on the configured host. The transferred
archive has SHA-256 `b91a7169c5a342d0444a5d5a88326ab5fe32bb0e732440a66a7bf3c4c62a4a87`;
the remote host verified it before extraction. The resource check passed with
35 GiB free. All nine native Linux suites and checked documentation are running.
Offline installed acceptance of the same source also started on macOS.
These runs are not reported as passes until their terminal results succeed.

Published draft PR #79. Integrated main `b1d1828b`, whose only change since
the tested base records parser task completion in plan files. Runtime source
and all test inputs are unchanged by that integration. Final owner review is
not requested yet; Linux, installed and hosted acceptance remain pending.
