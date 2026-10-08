# Bundle readiness status

Status: IN PROGRESS. Harness validation has resumed; performance trials remain held.
Created 2026-10-06.

Task: [bundle attack parity and cold-run measurement](20261006-bundle-readiness.task.md).
Source: [issue #30](https://github.com/vihren-dev/sqlite-verifier/issues/30).
Specifications: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md),
[data path](../docs/data-path.md), [kernel gate](../docs/kernel-gate.md).

## Progress

- 2026-10-06: Read the approved product T06 card and owner review before work.
  Created isolated Jujutsu workspace `bundle-readiness` from reviewed exporter/
  upgrade `07dc71b3`, then merged published main `29d2ed7a`. Only the review
  journal conflicted. Preserved all 63 raw lines and both parent orders; no
  reviewed feature commit was rewritten.
- Read issue #30 (open, no comments), the full kernel attack inventory, existing
  bundle tests and both drivers. The direct checkers return 2 for a checked
  refutation; both public CLI paths currently report `VIOLATED` with exit 1.
  The task states this boundary explicitly and preserves the public protocol.
- Current reports do not expose stage timings. The older stage-timing experiment
  references a replaced parser caller and runs in process. New observation must
  follow current command callers while preserving fresh process boundaries and
  acceptance behavior.
- Attack parity and a tested measurement harness are authorized now. Actual
  performance trials wait for the final installed runtime and idle-host
  coordination. T06b cutover is outside this task. No performance trial or
  owner-held full model gate has started.
- 2026-10-06: Planning/base checkpoint `493e049a` passed independent review
  with no findings. Added exact integer-nanosecond median bounds. The approved
  continuation needs joint coverage: closest fixed-size 95% intervals at both
  looks would jointly cover only 92.7211%. Predeclared ranks are 2–8 at nine and
  7–19 at 25, retaining the initial nine. Fixed-size coverages are `123/128` and
  `8265855/8388608`; simultaneous coverage is `1994151/2097152` (95.0885%).
  Root confirmed this interpretation before observations; no time tolerance was
  added. All 17 pure tests pass in 0.03 seconds (30-second bound), including
  independent sign counts, conservative trinomial ties, exact rank bounds,
  one-nanosecond decisions, zero and invalid evidence. No performance run began.
- 2026-10-06: Statistics review `395b748c` confirmed the arithmetic and tie
  calculation, with five `should` findings and no `must` findings. Documented
  the predeclared counts, ranks and named 95% requirement, clarified coverage
  for caller-supplied ranks, and added received count/index/type diagnostics.
  Added invalid-rank/count tests at both looks. Resolved
  `20261006T164839Z-395b748c#1` through `#5`. All 30 statistics checks pass under
  the 30-second bound. Three new observer checks also pass in the working copy;
  their feature will be recorded separately.
- 2026-10-06: Confidence-policy cleanup `6df37baa` passed independent review
  with no findings. Added a stage observer that runs the actual installed
  launcher under its pinned isolated Python, retaining source-hashed nested
  spans from that invocation. It does not replace driver functions or change
  reports/exits. Four bounded child/current-caller tests preserve positive and
  `VIOLATED` protocols, prove fresh PIDs and bind spans to the same external
  monotonic wall interval. The combined 34 pure/child checks pass in 0.34 seconds
  (30-second bound). These are harness fixtures, not performance evidence.
- 2026-10-06: Observer review `461a4186` found three `should` findings and
  no `must` findings. Documented the selected stage policy, named external
  process-role classification, and added same-process dependency/compile/checker
  spans plus exception-ending stage coverage. Resolved
  `20261006T170020Z-461a4186#1` through `#3`. All 35 statistics/observer checks
  pass in 0.50 seconds (30-second bound). Public reports/exits remain unchanged,
  and each exception path leaves zero active stage frames. No performance trial
  or acceptance cutover occurred.
- 2026-10-06: Observer process-role cleanup `3863ae85` passed independent
  review with no findings. Extracted the unchanged private kernel fixture and
  exact 12-case proof-attack inventory into flat helpers for both checker suites.
  Updated the kernel target's explicit Nix inputs. All 19 existing kernel cases
  pass against the cached reviewed Lean 4.34.1/T02 Darwin runtime (120-second
  suite bound; each compile/check remains bounded). No actual timing trial ran.
- 2026-10-06: Shared fixture/inventory checkpoint `5062c3e9` had no `must`
  findings. Its two `should` findings described the second caller before it
  existed. Added that caller and resolved `20261006T171202Z-5062c3e9#1` and
  `#2`. All 23 independently selected bundle attacks pass in 29.08 seconds
  against the cached reviewed T02 Darwin runtime (150-second bound). Actual
  exports cover applicable source attacks and controls; handwritten valid
  records cover forged bodies, protected substitutions, unsafe/partial proofs
  and hostile headers. Refutation returns direct checker 2; public CLI stays 1.
  The review matrix explains why the old compiled-`SqlInputs` profile mutation
  does not apply directly and tests the corresponding changed profile record
  against the actual frontend request. No checker/exporter source changed.
  Added exact shared fixture inputs to both Nix suites and the new bundle
  caller to its ownership manifest. All 37 pure inventory/statistics/observer
  checks pass in 0.51 seconds (30-second bound). Nix infrastructure and ordinary
  integrated checks remain to run after coordinated assembly; full model is
  owner-held and timing trials remain held for the final runtime.
- 2026-10-06: Attack checkpoint `5ae0e253` passed review with no `must`
  findings and two `should` findings. Reused current preparation's export roots
  and protected base constant, and gave the fixture header its actual library
  import. Clarified the complete malformed-header test scope. Resolved
  `20261006T172148Z-5ae0e253#1` and `#2`. All 23 direct bundle checks pass again
  in 28.68 seconds under the same 150-second bound. No trusted/checker code or
  public protocol changed, and no performance trial began.
- 2026-10-06: Attack export cleanup `791ec7e6` had no `must` findings.
  Named and documented the four fixture-only compiled-module omissions,
  including why fixture-owned `SqlInputs` differs from production preparation
  and why handwritten protected records remain necessary. Resolved
  `20261006T172547Z-791ec7e6#1`. The omitted set and behavior are unchanged from
  the passing 23-case checkpoint; the 37 pure checks remain passing.
- 2026-10-06: Fixture-boundary documentation `d4441c8d` had one `should`
  finding and no `must` findings. Named KernelCase, BundleCase.export and
  production export_bundle directly and stated which definitions each owns
  or omits. Resolved `20261006T172800Z-d4441c8d#1`. Behavior and the previously
  checked omitted set are unchanged; this is a documentation correction.
- 2026-10-06: Final fixture wording `508260f4` passed independent review
  with no findings. Added full byte/link/mode identities for actual runtime,
  explicit source roots, observer and pinned Python. Hashing occurs outside
  command timing and its OS-cache warming is stated as an observation limit.
  Cold directories must be new and remain intact when refused. Added a bounded
  fresh-process recorder with exact raw stdout/stderr, externally measured
  wall intervals and source/process/parent-bound same-invocation stage traces.
  The observer journals actual runtime-created process groups for timeout
  cleanup. Partial/malformed journals and incomplete cleanup invalidate the
  observation, preserving its raw evidence. Deadline waiting uses pipe events
  rather than process-exit polling. All 48 pure/child/inventory checks pass in
  2.99 seconds (30-second suite bound), including real new-session timeout
  cleanup, invalid UTF-8 output, changed identities and malformed stage traces.
  These deterministic fixtures are not performance evidence. No coordinated
  timing trial, heavy Nix check or held full-model gate started.
- 2026-10-06: Process checkpoint `ed3bbd4d` had four `should` findings and
  no `must` findings. Named the bounded cleanup-output deadline and shared the
  trace-to-process-journal rule with the observer and tests. Added host identity
  field/type checks plus actual expired-before-launch, missing-executable and
  escaped-descendant open-pipe cases. The escaped fixture is explicitly stopped
  by its test after incomplete cleanup is recorded; no sandbox claim is made.
  Resolved `20261006T173541Z-ed3bbd4d#1` through `#4`. All 52 focused checks pass
  in 5.16 seconds under the 30-second bound. Raw failed observations stay intact
  and cannot become timing acceptance. Actual performance remains held.
- 2026-10-06: Cleanup-policy checkpoint `847dbd2b` had one `should`
  finding and no `must` findings. The escaped-pipe test now waits for actual
  child readiness and injects its timeout after that handshake; it does not
  assume the child becomes ready within the measured timeout. Its bounded
  readiness wait is separate test setup. The fixture records its escaped PID
  before completion and stops it in `finally`. Resolved
  `20261006T174416Z-847dbd2b#1`. Also subtract actual process startup from the
  remaining common deadline before waiting. All 52 focused checks pass; no
  performance acceptance or actual trial is inferred from fixture durations.
- 2026-10-06: Timeout-handshake checkpoint `3f08d30f` had two `should`
  findings and no `must` findings. Retained the timeout-injection timestamp
  and asserted bounded cleanup separately from fixture readiness. Added a
  controlled-clock test around actual Popen creation; it fails if startup
  does not consume the common deadline and verifies the killed process still
  has a retained receipt. Resolved `20261006T175244Z-3f08d30f#1` and `#2`.
  All 53 focused checks pass under the 30-second bound. No timing trial began.
- 2026-10-06: Startup-deadline validation `a66d22b0` passed independent review
  with no findings. Added complete current path recording, immutable argv/source
  contexts, source-root guards, one shared preparation/checking deadline and
  observed checker exits distinct from public CLI exits. New directories and
  active-cache observations prevent warm reuse. Runtime/source/measurement-code
  byte identities are retained before and after each path. Whole external path
  wall includes startup, observation and inter-command work; spans come from
  those same invocations. Exact nine-to-25 protocol/report pure tests retain both
  declared looks and every raw difference; invalid pairs suppress acceptance.
  All 93 focused protocol/path/process/identity/statistics/inventory checks pass
  under a 30-second suite bound. The fixture checks are not performance evidence.
- 2026-10-06: The owner requested no new tasks and an immediate checkpoint of
  existing work, allowing incomplete validation to be recorded explicitly.
  Preserved all current tools/tests in this checkpoint and set this own task
  and status to HELD. No benchmark, new task, heavy Nix job, push or PR started.

## Remaining acceptance at the held checkpoint

- The campaign writer is a draft: it has not passed end-to-end campaign,
  interruption or invalid-pair persistence tests. It must not be used as
  acceptance evidence yet. Pure continuation/report calculations are checked.
- The named small/refutation/Atuin case launcher and documented execution
  entrypoint are not implemented. No actual performance trial has run.
- Retained artifact manifests describe files that survive each current driver.
  Private compiler workspaces removed by those drivers are not recovered here.
- Ordinary combined source/development checks and Nix infrastructure checks
  for these new inputs remain incomplete; cached short kernel/bundle checks
  do not substitute for those integrated gates.
- Final installed T05/documentation runtime, idle macOS/Linux leases, all actual
  nine-or-25 raw trials and owner dispositions remain required. The earlier
  owner-held full model gate also remains held; it was not started here.
- Checkpoint `324ca1e88254a515c59013801b9e89b17fde6efc` passed independent
  review `20261006T182144Z-324ca1e8` with 0 must and 6 should findings. Their
  explicit deferrals are recorded below. T06 is not DONE; no cutover or
  performance claim is made.

## Held checkpoint review deferrals

The owner requested an incomplete checkpoint and a switch to the already-started
T04c task. The list below records the former `20261006T182144Z-324ca1e8`
deferrals. Continued harness validation resolves them; the append-only journal
preserves each original reason and subsequent outcome.

- #1: Campaign persistence/end-to-end tests remain incomplete; no acceptance use.
- #2: Include pair/directory details in the held draft's machine-change error.
- #3: Include output/root/action details in the held draft's output-path error.
- #4: Name the existing checker/status mapping; observed 0/2 versus CLI 0/1
  has focused coverage, but the policy cleanup remains pending.
- #5: Clarify that evidence_identity also hashes measurement-policy sources.
- #6: Complete static typing of the runtime-tested deadline-forwarding wrapper.

No new campaign, launcher, benchmark or task was started after the hold.

## Continued harness validation

- 2026-10-06: Continued this already-started task after the requested checkpoint.
  The owner permits completion of active tasks while the four reviews proceed.
  Performance trials remain held for the final installed runtime and idle hosts.
  No unstarted card or frozen review branch changed.
- Named the existing checker exit policy without changing its values. Clarified
  the measurement-policy source hashes in the identity function. The real-child
  deadline test now forwards explicitly typed parameters. These corrections
  address deferred findings `20261006T182144Z-324ca1e8#4`, `#5` and `#6`.
  Campaign tests, launcher work and other acceptance checks remain incomplete.
- All 28 focused path, identity and child-observation checks pass in 1.60
  seconds under the 30-second limit. The three deferred findings are recorded
  as fixed in the append-only review journal. No performance trial ran.
- Cleanup review `20261006T190500Z-ca291f9a` has no must findings and one
  should finding. Named the public CLI exit policy as well as the independent
  checker policy, including successful preparation. Their values are unchanged.
- All 28 focused checks pass again in 1.54 seconds under the same 30-second
  limit. The finding is fixed. Campaign persistence checks remain the next
  unfinished harness requirement; no performance campaign has started.
- Root cleanup `cfc24b4987a6366fa5517e56b0c64be2a8ae2c47` passed review
  `20261006T191704Z-cfc24b49` with no findings. Preserved its exact pending
  review row during the campaign handoff.
- 2026-10-06: The campaign writer now records each completed path and the
  pending flow before another invocation. An interruption retains partial raw
  files and its condition without inventing a duration. Metadata replacement
  uses complete temporary JSON and an atomic rename; failed replacement retains
  the previous record and unfinished bytes. Existing evidence is not overwritten.
- A host change or failure to observe the host after both paths invalidates the
  actual retained pair and summary. Machine-change errors name the pair/output
  and require a new campaign directory. Output-root refusals name the output,
  selected input root and action. These corrections resolve the former
  `20261006T182144Z-324ca1e8#1`, `#2` and `#3` findings.
- The 17 new bounded writer checks use explicitly synthetic observations and
  real retained files. They verify decisive nine-pair stopping, retention of
  the same first nine through 25, invalid/interrupted pairs, post-pair machine
  drift, output guards and metadata write failures. All 108 measurement
  harness checks pass in 4.21 seconds under a 30-second command bound. JUnit:
  `build/test-results/t06-harness.xml`. Existing real-child tests remain the
  subprocess-boundary evidence; synthetic intervals are not performance data.
- Files in this unit remain below 200 lines. Named-case launcher work, ordinary
  integrated/Nix checks, final installed runtime, coordinated hosts, actual
  performance trials and owner dispositions remain incomplete. No actual
  performance campaign, SSH job, heavy Nix job, publication or frozen review
  branch change occurred. T06 remains IN PROGRESS.
- Persistence checkpoint `efbce3b814a3727145913f2fb2754ae42f4c2337` passed
  review `20261006T193034Z-efbce3b8` with no must findings and two should
  findings. Named the shared interruption-exception policy and added actual
  writer checks for ordinary path errors and `SystemExit`. Each retains its
  distinct pair, summary and campaign state plus the original failure condition.
  Both findings are fixed; all original review rows remain in the journal.
- All 110 measurement harness checks pass in 4.26 seconds under the same
  30-second bound. This includes 19 synthetic writer checks and the existing
  real-child boundary checks. No actual timing trial or acceptance cutover ran.
- Cleanup `876628e5` passed independent Claude review with no findings. The
  campaign-persistence unit is checked within its synthetic writer scope and
  ready for coordinated integration. Its exact raw review row is preserved in
  this checkpoint. The named-case launcher, integrated gates, final runtime and
  actual owner-reviewed performance observations remain pending; T06 is not DONE.
- 2026-10-07: Continued only the next unfinished T06 launcher requirement.
  Added `tools/bundle_measurement.py` and the team execution guide
  `docs/bundle-measurement.md`. The three configurations use shipped small
  success/refutation sources under profile 3.51.0 and Atuin under 3.46.0. They
  share protected role arguments between paths and retain full Lean source
  directories. `TrialSpec` remains the flexible manual-argument primitive.
- Runtime, Python, output and common timeout are required explicit selections.
  The named wrapper checks the executable Python against `runtime/python-path`
  and refuses missing selected files before campaign evidence creation. All 24
  new bounded launcher cases pass in 0.71 seconds. Tests parse the actual source
  CLI and exercise the actual writer with explicitly synthetic observations;
  they do not execute installed verification paths or establish timing evidence.
- Final installed T05/documentation runtime, ordinary integrated/Nix gates,
  coordinated idle hosts and actual owner-reviewed macOS/Linux campaigns remain
  required. No actual trial, heavy Nix/SSH job, publication, runtime/proof-gate
  change or frozen review branch change occurred. T06 remains IN PROGRESS.
- The combined measurement harness now passes all 134 checks in 5.35 seconds
  under a 30-second command bound. JUnit is retained at
  `build/test-results/t06-launcher-harness.xml`. New source/test files contain
  79 and 160 lines. The prior campaign receipts and append-only review rows are
  unchanged; the pending exact checkpoint review row is included in this unit.
- Launcher checkpoint `4be027d9` passed review `20261007T063405Z-4be027d9`
  with no must findings and three should findings. Moved each source layout and
  identity root into the named case definition. Added distinct malformed
  `python-path` diagnostics and positive `--timeout-seconds` validation in the
  units supplied by the caller. The bounded tests check both diagnostic changes.
  These three findings are fixed; every prior raw journal row remains intact.
- All 135 measurement harness checks pass in 5.32 seconds under the same
  30-second command bound. The additional check covers a relative declared
  Python path. JUnit is `build/test-results/t06-launcher-harness-reviewed.xml`;
  the prior receipts are retained. The launcher and test files contain 99 and
  178 lines. Installed-runtime execution and actual campaigns remain pending.
- Cleanup `af3b9ccdf277ce819b2fc248ff1d00ce5a64ff46` passed independent review
  `20261007T063538Z-af3b9ccd` with no findings. The named launcher/configuration
  unit is checked within the bounded parser and synthetic writer scope. This
  status-only checkpoint does not change source or test behavior. The exact raw
  cleanup review row remains pending for the next journal-containing commit.
  No installed execution contract, integrated gate or performance acceptance is
  claimed; T06 remains IN PROGRESS.

- 2026-10-08: Prepared current-main integration with accepted `d75fdc2b`.
  The two conflicts are resolved. All feature source hashes remain exact,
  and all three original journals remain ordered subsequences of 314 rows.
  Integration checks have not run. The resource guard stopped validation
  with 9.56 GiB free, below the required 10 GiB. No test, Nix build or
  performance campaign started after that refusal. Targeted cleanup of one
  completed 2.39 GiB pytest directory is proposed in
  `build/20261008-t06-main-integration/cleanup-proposal.json`. The owner has
  been asked for approval; no directory is removed. The pending integration
  remains uncommitted until its checks can run.

- 2026-10-08: The owner instructed cleanup of the proposed directory.
  Removed only `/private/tmp/nix-shell.tUn6jh/pytest-of-tzankomatev/pytest-0`
  after verifying its directory identity and absent pytest lock. The
  cleanup receipt records 12,032,352,256 free bytes afterward, about
  11.2 GiB. The resource guard passes. Repository files, retained evidence,
  archives, the Nix store and all other temporary paths are untouched.
  Ordinary integration validation resumes; actual timing remains held.

- 2026-10-08: Current-main integration passes 137 bounded measurement
  and attack-inventory checks in 6.17 seconds, eight actual Nix command
  and dependency checks in 17.90 seconds, and complete ordinary source
  acceptance with 507 tests and 35 subtests in 50.32 seconds. Actual
  macOS Nix sandboxes pass all 65 bundle tests in 325.39 seconds and
  all 28 kernel tests in 48.21 seconds. No failure, error or skip occurs.
  Production Lean, application, examples, conformance and CI files match
  accepted main. Original XML, console bytes, source hashes, all parent
  journals and the authorized cleanup receipts are retained in
  [the integration record](../reports/20261008-bundle-readiness-main-integration/README.md).
  These are correctness checks, not performance evidence. Remaining
  ordinary Nix acceptance, independent review, installed execution and
  actual cold campaigns remain. T06 is not DONE.

- 2026-10-08: Checked integration `849bceae` passes independent review
  `20261008T073925Z-849bceae` with no findings. The reviewer could not
  run hashing commands. Author checks verify every retained artifact hash
  and the original decompressed native-gate log. The acceptance record
  now identifies the team as its sole audience. Remaining seven-suite
  ordinary Nix acceptance is running. The actual cold campaign is held.

- 2026-10-08: All seven ordinary macOS Nix suites pass 333 checks.
  Atuin, CLI, sample and upstream execute freshly; bundle and kernel use
  their retained fresh earlier gate outputs. Harness uses its matching
  cached output with 126 checks and its original timestamp. This differs
  from the 137 host harness and inventory checks. The original XML files
  retain separate names. Model and frozen are outside the ordinary recipe.
  Complete console bytes and exact output/execution metadata are retained.
  Evidence review, Linux correctness acceptance, installed execution and
  actual cold campaigns remain required. T06 is not DONE.
