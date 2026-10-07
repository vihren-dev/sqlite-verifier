# Hosted macOS model-suite timeout status

Status: DONE. Created 2026-10-06.

Task: [hosted model timeout](20261006-hosted-model-timeout.task.md).
Workspace: `sqlite-verifier-hosted-model-timeout`.
Bookmark: `codex/hosted-model-timeout`.
Base: public main `29d2ed7ab7621373e5bb33c97ce8c325fad1b41f`.

## Progress

- 2026-10-06: Created a separate Jujutsu workspace/bookmark for the explicitly
  authorized timeout investigation. Frozen PR branches are unchanged. T18b
  native acceptance is retained separately at `d066779c`; its public source is
  `dac12b49`, and its remaining acceptance is hosted CI artifact retention.
  No heavy native rerun is authorized while PR #48 holds both host leases.
- 2026-10-06: Retrieved current PR metadata read-only. PR #43 source is
  `6917e3c8`, PR #44 is `d08d91ee`, and PR #47 is `07dc71b3`. Actual hosted logs
  and cache/test progress must establish the deadline and cause before code
  changes. Public main's shared pytest recipe currently uses a 420-second
  timeout; the reported 600-second cutoff must be located in the executed job.

## Acceptance remaining

No timeout-task acceptance remains. The published 600-second recipe passes the
complete hosted check on both native systems and is adopted on main through
PR #49 at `d8faab74`. This local receipt update performs no merge or repush.
T03's frozen-source hosted macOS result and its
separate owner/release gates remain open; this main-based source uses Lean 4.33.0.

## Checked investigation

- 2026-10-06: Retained five complete decoded hosted job logs with original and
  compressed SHA-256 bindings. Actual model deadline is 420 seconds; 600 seconds
  belongs to later host checks. PR #43, #44 and main time out near the final
  cases with exit 124 and no model JUnit. PR #47 freshly runs all 323 cases,
  322 passed/one Tcl skip in 300.70 seconds. PR #43 hosted Linux passes the same
  count in 222.42 seconds. Exact head/merge/runtime identities and temporary
  T03 platform evidence are in the [report](../reports/20261006-hosted-model-timeout/README.md).
- 2026-10-06: The ordered 32-file ownership list is identical in all four
  checkouts. Progress and both final test files are byte-identical. Buffered
  logs cannot isolate why execution speeds differ; the measured historical
  work and repeated frozen loads explain the aggregate budget pressure.
  Only the full model deadline increases to 600 seconds, approximately twice
  the measured passing macOS time. Six other deadlines, all cases, subprocess
  limits and complete report flags remain unchanged.
- 2026-10-06: Real Nix command/ownership evaluation and existing CI scope/check
  tests pass: 10 cases plus 28 subtests in 1.49 seconds. No heavy native rerun
  or frozen-branch change occurred. Independent review and the authorized
  separate draft PR still follow. The new hosted model result is required
  before this task can be DONE.
- 2026-10-06: Both native-system flake projections reuse all seven real test
  targets (two evaluation checks, 6.53 seconds). Markdown local links resolve.
  All five compressed logs reproduce their retained decoded bytes and hashes;
  four source comparisons preserve the same complete 32-file model inventory.
- 2026-10-06: Feature checkpoint `a14bc8ab` passed independent Claude review
  with zero must findings and one should finding: name the aggregate deadline
  policy outside the builder. The correction uses one named attribute set
  with a 420-second default and the 600-second full-model override. This is a
  naming correction; the rendered commands and ownership are unchanged.
- 2026-10-06: Corrective checkpoint `7101799d` passes the real rendered-command
  check in 1.06 seconds and independent Claude review with zero findings
  (`20261006T183741Z-7101799d`). The original R1 should finding is recorded as
  fixed. Source checks are complete. The separate authorized draft publication
  will request the actual hosted result; merge remains held until that check
  completes and the owner receives its context.
- 2026-10-06: Published the reviewed source as separate draft
  [PR #49](https://github.com/vihren-dev/sqlite-verifier/pull/49), exact tip
  `b78834000049bfca9ad57bbc6d522827fe35b9ae`, base public main `29d2ed7a`.
  The PR is attached to this task. No frozen PR was updated. Hosted acceptance
  remains outstanding; this local status checkpoint does not repush the branch
  or cancel its initial CI run. Pending raw clean review
  `20261006T183741Z-7101799d` remains unchanged in the working-copy journal.
- 2026-10-06: Hosted [CI run #87](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37512848112)
  has started for the exact published tip. Darwin job `112438177629` and Linux
  job `112438177974` are in progress. Initial routing selects complete checks;
  prerequisite restoration is in progress and the model phase is pending at
  this snapshot. No hosted pass is claimed. This launch receipt remains local
  to avoid restarting CI.
- 2026-10-06: PR #49 Linux job `112438177974` completed with success. Exact
  executed merge `4056410cc327dffc6a457368ed2061199a0b8ade` contains the reviewed
  600-second model policy. Its model builder ran freshly: 322 passed and one
  existing Tcl skip in 177.33 seconds (original JUnit: 177.327). The case-report
  ZIP matches GitHub digest `400d37b971570edc23e054e01aba6c91074af72bc84a28b0b9f34f237a51c723`.
  All ten original XML reports have zero failures/errors. Original ZIP, full
  decoded log and exact artifact/source/runtime identities are retained in
  `reports/20261006-hosted-model-timeout/acceptance/linux/`. Other Nix suites may
  reuse successful outputs; only the model builder is claimed fresh here.
  Darwin remains in progress, so required whole-check acceptance is incomplete.
- 2026-10-06: Separate PR #48 local Darwin evidence strengthens the budget
  rationale. Reviewed mutation-corrected source `9e3b4419`, validated with only
  the reviewed 600-second model invocation override, completed 323 cases with
  322 passed/one Tcl skip in 484.735 JUnit seconds (487.2766 full invocation).
  Its earlier configured-420 source `83edc417` failed without JUnit after a
  422.825-second file-write interval and a Nix formatting error. Exact paired
  identities and original receipt hashes are retained in the qualified record;
  they are separate sources and are not a hosted PR #49 result or a passing
  claim for PR #48's unchanged configured 420-second branch. Frozen branches
  and their original failure receipts remain unchanged.
- 2026-10-06: Receipt checkpoint `92e3646e` review found zero must findings
  and two documentation should findings. Corrected the PR #48 count to
  322 passes/one Tcl skip and added its 484.735-second duration and remaining
  115.265 seconds to the deadline rationale. No code, source membership,
  branch deadline or original artifact changed. Hosted Darwin is still pending.
- 2026-10-06: Receipt correction `b0f81749` passed required independent Claude
  review with zero findings (`20261006T185508Z-b0f81749`). Both earlier R13
  findings are recorded as fixed. This evidence-only local checkpoint does
  not update the published source. Darwin whole-job acceptance remains pending.
- 2026-10-06: Hosted run `37512848112` completed with success on both systems
  at `2026-10-06T19:04:16Z`. Both executed merge `4056410c` from published
  reviewed head `b7883400`. Darwin's fresh model builder has 322 passes and one
  existing Tcl skip of 323 cases in 411.41 seconds (JUnit: 411.368); Linux's
  fresh model takes 177.33 seconds. Exact ordered case identity digests match
  across both original XMLs and cover every one of the 32 owned files.
  Darwin's original case-report ZIP matches GitHub digest
  `94566fa260e88e8187b93df42a4acd93ea230c5d1666b29670bbfa2dca4ceb92`.
  All 20 retained original XML reports have zero failures/errors. Both whole
  jobs include successful infrastructure and installed acceptance. Original
  report ZIPs, decoded logs, runtime/recipe/artifact identities and the run's
  completed status are retained in the acceptance directory. Release was
  skipped, and this task does not merge, repush or change any frozen PR source.
  The timeout task is DONE; final receipt review follows before handoff.
- 2026-10-06: Final CI receipt `5e0fda65` passed independent Claude review
  with zero findings (`20261006T190710Z-5e0fda65`). The reviewer verified counts,
  matching case digests and arithmetic; its session did not approve binary
  hashing. The author separately verified both downloaded ZIPs against GitHub
  digests and all 20 original XML/raw-log hashes before the commit.
- 2026-10-06: Coordinator adopted the tested head `b7883400` through merged
  PR #49 at main `d8faab74d80a58fa8ff194602f03018e1d6f3d25`. Read-only GitHub
  metadata confirms the merge. Adopted `build-support/tests.nix` has exact
  tested blob `0977664bc1ee5b38ff71c84c604f2a94b72fd5a9`. Task and status are
  DONE after both hosted completion and main adoption. Frozen PR sources,
  historical configured-budget failures and the separate T03 owner gates are
  unchanged. No receipt/status/log update has been repushed.
- 2026-10-06: Main-adoption receipt `37b2c4e3` passed independent Claude review
  with zero findings (`20261006T191028Z-37b2c4e3`). All required timeout-task
  work is complete. This local plans-only checkpoint preserves the latest
  pending raw review row for the next authorized receipt publication. Only
  checked receipt/status/log updates remain local; no feature code is pending.
- 2026-10-06: Prepared publication of only the checked reports, dated task/status
  and append-only journal on fetched main `d8faab74`. Every retained report and
  artifact is byte-identical to checked local tip `60201adc`; all main/local raw
  journal rows remain in their original order. The adopted recipe still has
  exact blob `0977664bc1ee5b38ff71c84c604f2a94b72fd5a9`. This integration contains
  no feature, code, Nix, workflow, release or protected-baseline change.
