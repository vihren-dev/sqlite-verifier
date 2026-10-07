# One SQL executor implementation status

Created 2026-10-06. Status: IN PROGRESS.
Task: [observable outcomes](20261006-single-sql-executor.task.md).
Sources: public issues #21 and #13.

## Current state

The executor implementation and requested mutation-harness correction are
checked and independently reviewed. Prior native ordinary/installed acceptances
remain retained. The complete model now passes natively on both hosts under
explicit recipes: Linux at the branch's 420-second budget, and Darwin through
the separately reviewed model-only 600-second validation invocation. The earlier
Darwin 420-second failure remains retained. Earlier PR #48 head `45ac63b2`
used 420 seconds. Published integration `8e10a593` now adopts the reviewed
600-second model policy from merged main; the other six suites retain 420.

Integration includes approved exporter source `07dc71b3` and its checked
publication record `555b9a74`, checked root documentation `db69c816` and
reviewed main `b91e5cb5`. Final source correction is `9e3b4419`.
Both hosted native checks pass at PR #48 head `45ac63b2`. The separate timeout
task is delivered in PR #49. The owner approved PR #48 on 2026-10-07, including
the target file and proposed protected baselines. The exporter owner approval
is also recorded. Publication integration, the recorded baseline exception,
merge and release remain pending. The protected-baseline failure remains an
expected failure; its guard is unchanged. T05 is not DONE.

Relevant definitions and callers are listed in the task file. The removed
executor's unconditional preservation law relied on treating data statements
as errors. Its replacement has an explicit CREATE/ADD guard and idle starting
state. The generated starting-schema pattern now matches the Atuin example.

## Progress

- 2026-10-06: Read both current public issues and confirmed their lack of
  additional comments. Audited execution, bridge, contract and preservation
  definitions and all caller names. Recorded outcomes and verification before
  substantial implementation. The approved small-example baseline currently
  binds two modules and omits its schema SQL; this is the exact intended change.
- 2026-10-06: Integrated the reviewed dependencies. Source files merged without
  conflicts. Preserved all raw review records from the four parents, including
  each parent's original order and repeated-line counts: 16, 24, 20 and 31 rows
  combine into 41 rows. Built runtime
  `/nix/store/mvdj3yfxpv1lcramgksv5qgsz78znkzl-sqlite-verifier-runtime-1`;
  its source suite passed 335 checks and 28 subtests in 33.93 seconds. All six
  ordinary Nix suites passed before feature changes: Atuin, bundle, CLI,
  kernel, development replay and upstream. Logs are retained locally as
  `build/t05-base-build.log`, `build/t05-base-source.log` and
  `build/t05-base-tests.log`; each Nix output retains its original JUnit XML.
- 2026-10-06: The dependency integration passed independent Claude review
  `20261006T160313Z-3b048277` with no findings. Removed the extension script
  evaluator, duplicate relation and bridge. Current invoice, failure, preservation,
  SQL regressions, all real kernel fixture modules and Atuin sources compile
  against the migrated SQL library. Every compiler call has a 30-second bound.
  The guarded schema-prefix law retains failure positions; it makes no claim for
  transaction prefixes. SQL contract conveniences require a support proof for
  every admitted database and retain the profile. A literal INSERT regression
  explains why the schema-preservation guard is necessary. The exact primitive
  `step` body SHA and all existing Contract target formulas are unchanged.
  All modified owned public declarations and fields have checked Verso docs.
  Built current runtime
  `/nix/store/74b05piwizmdwn54rrcjyb7gvqxh73zc-sqlite-verifier-runtime-1`.
  Source checks passed 336 cases and 28 subtests. Ordinary Nix suites passed
  12 Atuin, 42 bundle, 13 CLI, 19 kernel, 12 development replay and 76 upstream
  cases, with no failures or skips. The expanded kernel suite then passed all
  28 cases, including real compiler rejection of retired declarations and the
  removed bridge import. Eleven affected native/model/kernel-law checks passed
  in 19.79 seconds. All 80 existing Nix infrastructure checks passed, followed
  by three new real identity mutations for both helper modules and the new
  kernel test. The latter prove exact source selection and target invalidation.
  Local logs use the `build/t05-migration-*`, `build/t05-kernel-api*`,
  `build/t05-model-short*` and `build/t05-new-inputs*` prefixes. The current-export
  JUnit properties retain actual inputs, all 130 compiled library-file hashes,
  executables, exact trust headers and two independently checked deterministic
  bundles per small/refutation/Atuin case. Installed acceptance, protected
  schema binding and final owner review remain pending.
- 2026-10-06: Migration review `20261006T164238Z-26fbe6fc` identified the expected
  R8 owner-review requirement and four documentation/exhaustiveness corrections.
  Recorded R8 as deferred only to final owner review, without approval. Replaced
  the schema guard's catch-all with every excluded constructor, documented the
  transition lemma's case-split proof and both helper modules' purpose, and
  clarified that a primitive success alone does not close a transaction. All
  migrated library proofs compile; the rebuilt source suite passed 336 checks
  and 28 subtests in 33.36 seconds. Every should finding is recorded as fixed.
- 2026-10-06: Correction `0eb80129` passed independent review
  `20261006T164844Z-0eb80129` with no findings. Both invoice interpretations now
  import sealed `SchemaInputs` and use `Generated.startSchema`; both proposed
  baselines pin the exact unchanged schema SQL plus updated interpretation
  sources. Requirements bytes and optional baseline-checker behavior are unchanged.
  The invoice proof reuse still checks by definitional equality. Current runtime
  `/nix/store/dv07xmydabx71bmkw4axpy4z1dfia0ph-sqlite-verifier-runtime-1`
  passed source 336 cases and 28 subtests, and all six ordinary suites passed
  184 cases with no failures or skips. Every invoice candidate checks its actual
  protected baseline; a changed schema comment rejects before a deliberately
  invalid proof through source and installed entrypoints. Content-verified offline
  Darwin archive SHA-256 is
  `c684a76b3bc53d16f34d3556d3a92c86badac3f61238e88bd28089dd4190d16c`.
  Its actual installed acceptance passed all 42 example, attack, current-export
  and removed-API cases in 191.26 seconds, with no skips. Logs use the
  `build/t05-schema-*` prefix; original XML is `build/test-results/t05-installed.xml`.
  The owner packet identifies exact proposed hashes and the unchanged CI guard.
  Native Linux, full model acceptance and final owner approval remain pending.
- 2026-10-06: Schema checkpoint `1432aec5` passed independent review
  `20261006T171020Z-1432aec5` with no findings. Reserved Linux acceptance completed
  from its reviewed public tracked snapshot in fresh directory
  `/var/tmp/sqlite-verifier-executor.ZNyERa/source`. Archive and helper SHA values,
  872 regular source files and one instruction symlink were checked before execution
  and remained unchanged after it. Actual runtime is
  `/nix/store/zfjrlz8kda2pxvp8dc4mn1i8hbb5qsys-sqlite-verifier-runtime-1`.
  Source passed 334 cases and 28 subtests, with only two existing optional
  reviewer-CLI checks skipped. All 184 ordinary, 83 infrastructure, 11 focused
  native/model-law and 42 actual installed cases passed without failures or skips.
  The content-verified Linux archive is 928,906,098 bytes, SHA-256
  `137c9bc90fad00a2f92748d95b8b18f52be4e922bbb367fceca20a289165335f`.
  Both platform receipts, 18 original XML files, exact Linux helper/snapshot and
  post-run source verification are retained under
  `reports/20261006-single-sql-executor/`. XML/helper hashes were checked locally
  after transfer. Vihren was released; earlier evidence directories are unchanged.
  No speed comparison or full model run is claimed. Full model acceptance and
  final owner review remain pending, so this task is not DONE.
- 2026-10-06: Evidence checkpoint `9bee3dd0` passed required independent review
  `20261006T174432Z-9bee3dd0` with no findings. Locally verified the two compressed
  payload hashes and all 18 exact original XML hashes after transfer, the executed
  helper and snapshot bindings, the current export identities/statuses, and the
  post-run source-unchanged report. All implementation should findings are fixed;
  the R8 owner marker remains deferred only to final owner review. Draft publication is recorded below; no issue closure, merge or release occurs.

- 2026-10-06: Prepared draft publication on the reviewed exporter branch.
  Retained the exact pending evidence-review row in a named journal change.
  Draft publication leaves final R8 approval, full model acceptance and hosted
  integration gates open; it authorizes no merge, release or issue closure.

- 2026-10-06: Draft PR48 is attached on `tasks/single-sql-executor`, head
  `2ef00198994c4f285bcae0853359fe20d148d6aa`, based on reviewed T02. Its checked
  journal publication commit passed independent review with no findings. CI run
  `37507080453` failed on both platforms: `test_stateful_modes[True]` reaches
  `conformance/mutation_check.py`, which still searches for the deleted
  `/-- Restricted extension helper` docstring. The model mutation check therefore
  never completes. Protected-baseline drift also fails the expected final owner
  gate; that guard is unchanged. T05 cannot pass until this source-owned harness
  bug is fixed and the full local model suite passes on both supported platforms.
  The latest owner review freezes PR43/44/47 and permits only this requested PR48
  correction. No T07 code or new T15/T18b integration is included.

- 2026-10-06: Replaced the removed-docstring extraction boundary with the actual
  `step` declaration and namespace closure. Four short pure regressions passed
  in 0.48 seconds: changing/removing every declaration docstring leaves the
  shadowed production transition unchanged, and missing code boundaries fail
  before partial model compilation. XML: `build/test-results/t05-mutation-source.xml`.
  Lean source and frozen native inputs are unchanged. Targeted native mutation
  validation and both full local model runs await coordinated host leases.

- 2026-10-06: Correction `941c1aa4` passed independent review with no must and
  one should finding: document that the extraction spans the primitive definition
  through the namespace close and requires it to remain the final declaration.
  Added that explicit warning and recorded the finding as fixed. The actual
  error-seeking generation/mutation check plus four source regressions then
  passed all five cases on Darwin in 10.56 seconds. Current conformance artifact
  is `/nix/store/3h1ww180anyrw23dhs7bpzswhkrv2l1s-sqlite-verifier-conformance`.
  Its original XML is `build/test-results/t05-mutation-targeted.xml`; log is
  `build/t05-mutation-targeted.log`. Both host leases are now reserved for the
  required complete model runs. Full acceptance and final owner approval remain
  pending; no new baseline, issue closure, merge or release is authorized.

- 2026-10-06: Correction review `20261006T182507Z-83edc417` had no must and
  requested the exact boundary names in the warning. Named `def step`, the last
  `end SqliteVerifier` and `Execution.lean` explicitly and recorded that should
  finding as fixed. The extraction body is unchanged; all four pure regressions
  passed again in 0.49 seconds. A full Darwin model run for `83edc417` is live,
  but no full acceptance is claimed. Final source identity must be retained for
  both required local native gates after this documentation correction.

- 2026-10-06: Final correction `9e3b4419` passed independent review
  `20261006T182707Z-9e3b4419` with no findings; both prior should findings are
  fixed. The first complete Darwin Nix model attempt, using the preceding
  doc-only `83edc417` checkpoint, is terminal exit 1. Its raw log ends during
  `test_actual_frozen_partition_requirement_inventory_and_identities[5]` with
  `error: boost::bad_format_string: format-string is ill-formed`, without a pytest
  summary or successful JUnit output. The actual generator/mutation case passed
  inside that attempt, but the complete model gate did not pass. The 420-second
  suite and 900-second outer bounds are unchanged. Log:
  `build/t05-model-full-darwin.log`; derivation:
  `/nix/store/jm2cxh55awywml9691qmyda6c4yaxmr1-sqlite-verifier-test-model-1.drv`.
  Stopped dependent Darwin reruns and reported the external Nix failure for
  feedback. No deadline, denominator, case membership or baseline was changed.
- 2026-10-06: Linux final-source targeted validation is terminal 0: the actual
  generator/mutation case plus four source cases passed in 18.85 seconds. Reviewed
  public snapshot `9e3b4419` is in fresh retained directory
  `/var/tmp/sqlite-verifier-mutation.tql5Ir/source`; its compressed archive SHA
  is `684a123180dbfed30324249fbcc42941f96a8c09ebba2d26d3b0f3034cb97689`,
  and executed helper SHA is
  `78aedf6a2a951cc718450d3eaf45e1c3604196d68fbbec0263c04ed737e0fffb`.
  All 881 tracked regular-file hashes and the instruction symlink were verified
  before execution. The already-started complete Linux gate remains live; it is
  not claimed as passing. Earlier task directories and receipts are untouched.

- 2026-10-06: Linux full final-source gate is terminal 0: 322 passed and one
  existing Tcl-capture skip in 328.30 seconds, under its unchanged 420-second
  suite budget. Both original XML files, every raw log, actual output/derivation
  identity and all 881 unchanged source hashes were verified after transfer.
  Linux and Darwin host leases are released.
- 2026-10-06: The owner authorized one final Darwin validation using only the
  install-phase budget equivalent to independently reviewed timeout task
  `7101799d`. The override changes model 420 to 600 seconds; all 32 ordered
  files, flags, source and other targets remain unchanged. All 318 realized
  immutable model source files match final reviewed `9e3b4419`, before and after
  the run. The complete gate is terminal 0: 322 passed and the same existing skip
  in 484.74 seconds; the full invocation took 487.2766 monotonic seconds. Output:
  `/nix/store/m0l8bxww097w76m4c81k4g7gmdjp3kya-sqlite-verifier-test-model-1`.
  The 900-second outer bound remains unchanged. This is native full validation
  under the separate reviewed 600-second recipe, not a passing claim for PR48
  configured CI at 420 seconds. No timeout commit is merged into this branch.
- 2026-10-06: Retained the earlier Darwin configured-budget failure and the
  complete paired native validations in the new `full-model/` report subdirectory.
  Four original XML files and all raw logs/commands/source checks are retained
  with separate hashes in the 18-file raw payload. Metadata, exact Linux helper,
  public snapshot, private Darwin override/caller and source/file order were
  independently verified locally. Prior immutable reports and baselines are
  unchanged. Final hosted, timeout-task acceptance and R8 owner gates remain open.

- 2026-10-06: Full-validation evidence `a247e0b1` passed required independent
  review `20261006T185138Z-a247e0b1` with no findings. Every mutation-correction
  should finding is fixed. The exact archived helpers and all prior receipts
  remain unchanged. Ready to update existing draft PR48 with only the requested
  correction and this qualified status/evidence. No separate timeout source is
  merged; no frozen PR, protected baseline, issue closure or release changes.
  T05 remains IN PROGRESS until its hosted, timeout-task and final R8 gates pass.

## Exporter checkpoints and remaining gates

The T03 and T02 receipts describe a fixed model and input checkpoint. Their
source hashes, native bundle bytes, helper bytes and JUnit receipts remain
immutable. T05 intentionally changes current proof APIs and approved inputs.
Its live regression must record the current input and library identities,
check bundle trust bindings, reproduce deterministic preparation and independently
verify the current success, checked refutation and Atuin cases. It does not
compare changed inputs with the old checkpoint or add an old-runtime path.

The protected-baseline CI guard remains unchanged. The owner approved the
proposed schema bindings; the expected drift failure remains separate from
proof acceptance. Earlier bounded work held the full gate for T13 feedback.
Complete local suites and both hosted native checks now pass, with every model
case retained. PR #49 delivers the model-only timeout correction. Passing tests
did not supply approval; the owner's explicit PR #48 approval did.

Publication integration, the recorded maintainer baseline exception, merge and
release remain open. Native ordinary, installed and full model validation under
the stated recipes are complete. The task is not DONE.

- 2026-10-07: The owner explicitly approved PR #48 at unchanged reviewed head
  `45ac63b2e07d6677c12187adafa1cdc96dc155d6`, after the mutation correction and
  complete native model results. Recorded the target-file and exact baseline
  approval in the owner packet and resolved the R8 finding. Both hosted native
  checks pass; the deliberate protected-baseline failure remains recorded.
  Integration will preserve the approved executor and proof sources. No guard,
  expected failure or frozen checkpoint is changed to manufacture a pass.
- 2026-10-07: Integrated reviewed main `bc9e2dce`. The only conflict was the
  journal; all 71 main and 104 task rows survive in their original orders,
  with 126 combined rows before approval resolutions. All 74 approved Lean,
  exporter, runtime-pin, mutation-source and baseline files remain byte-exact
  `45ac63b2`; all three proposed baselines are unchanged. The retired exporter
  patch remains absent. No Python runtime source changed in this integration.
  All seven focused source-boundary and actual Nix-routing checks pass in
  8.00 seconds under 120 seconds, covering both platforms and full suite
  ownership. The current published head and its historical complete local
  model evidence remain separate from this publication integration. Recorded
  the already-given exporter approval in this combined journal; no guard or
  proof source changed.
- 2026-10-07: Main integration `4313281b` passed independent review
  `20261007T075223Z-4313281b` with no findings. Integrated the checked exporter
  publication record `28556a43`; its approved source is unchanged. The only
  conflict was the journal. Both parent orders and repeated-row counts survive:
  129 executor rows and 82 exporter rows combine into 140 exact rows. All
  74 approved source, pin and baseline files remain unchanged. This integration
  adds exporter acceptance records; it changes no runtime source or guard.
  All seven source-boundary and actual Nix-routing checks pass in 9.35 seconds
  under a 120-second bound. Original JUnit is
  `build/test-results/t05-exporter-integration-routing.xml`. The previous
  complete native model and installed results remain historical acceptance
  for the unchanged implementation; hosted integration is still pending.
- 2026-10-07: Exporter integration `4111dea0` passed independent review
  `20261007T080016Z-4111dea0` with no findings. Pushed only the existing PR #48
  feature branch and marked it ready. Its body records the owner approval,
  exact baseline exception and earlier failed budget separately. Fresh CI
  `37590978613` is running on Linux job `112692115126` and Darwin job
  `112692115395`. The exporter must reach main before this stacked PR is
  retargeted and merged. No hosted completion or baseline pass is claimed.
- 2026-10-07: PR #44 merged normally as `b91e5cb5` after both hosted platforms
  and protected baselines passed. Integrated the exporter's reviewed main
  refresh `555b9a74`. The incoming changes contain the accepted ADR, plans and
  receipt only. No production code or test input changed. All 74 approved
  source, pin and baseline files remain unchanged. The journal retains both
  parent orders and repeated rows: 88 exporter rows and 141 executor rows
  combine into 147 exact rows. The earlier seven source-boundary and routing
  checks remain valid for unchanged inputs; this refresh does not claim a new
  native test run. At published head `4111dea0`, protected job `112692365150`
  fails exactly because `examples/approved/baseline.json` changed. That expected
  failure remains separate from the running native jobs and the owner approval.
- 2026-10-07: ADR refresh `8e10a593` passed independent review
  `20261007T081309Z-8e10a593` with no findings. Verified that incoming receipt
  `b91-refresh.json` was covered by clean exporter review
  `20261007T080853Z-10ae1399`; its exact pending row is retained here.
  An initial journal-only lookup did not find that still-uncommitted exporter
  row; reading its task workspace confirmed the review and reviewed file.
  Published only the existing PR #48 feature branch. Current head is
  `8e10a593bf830c272bf6b5e6af525d943ce90212`; fresh CI `37592618106` is running.
  No source, timeout, baseline guard, main ref or earlier receipt changed.
- 2026-10-07: Current hosted run `37592618106` is terminal on both platforms.
  Linux job `112697692784` passes, with 42 bundle cases in 334.95 seconds,
  322 model passes and one existing skip in 323.07 seconds, and 76 upstream
  cases in 11.11 seconds. Darwin job `112697693167` fails because the bundle
  builder exhausts its unchanged 420-second budget. It collected 42 tests and
  completed 20 before stopping during the stage-reuse case. The stateful
  mutation case passes. No assertion or individual child timeout is reported.
  The unfinished model build is not evidence of a model timeout or a pass.
  The exporter has the same Darwin bundle failure; an isolated exact builder
  is being tested before any scheduling change. Merge remains held for this
  acceptance failure and the already-approved baseline exception.
- 2026-10-07: Integrated exporter head `eec6d08e`, which includes main
  `aeffab25` and the reviewed Darwin bundle schedule. Darwin now builds the
  complete bundle target before the complete recipe starts the other suites.
  Linux scheduling, all seven targets and their budgets are unchanged. All
  74 approved source, pin and baseline files remain byte-identical to
  `45ac63b2`. Both journal orders and repeated rows survive: 149 executor rows
  and 100 exporter rows combine into 160 rows. The exact final clean exporter
  review row is also retained. All 17 focused scheduling, failure-retention,
  routing and documentation checks pass, with 28 subtests, in 3.21 seconds
  under a 120-second bound. The first invocation named a nonexistent test
  file and ran no tests; the corrected invocation has complete JUnit at
  `build/test-results/t05-scheduling-integration.xml`. An initial supplemental
  review assertion used the wrong journal field name and stopped before any
  write; the corrected check confirmed the actual clean review. The isolated
  exact bundle receipt is a local pass, not proof of the hosted failure cause.
  Fresh hosted acceptance and exporter delivery remain required.
- 2026-10-07: The scheduling integration passed independent review with no
  findings. Jujutsu stopped the first push because the journal-only parent had
  no description; no remote changed. Added its description and reviewed that
  parent as `9fc40a76`, with no findings. The resulting integration `9e91e525`
  has exactly the earlier checked tree and passes its own clean review
  `20261007T092131Z-9e91e525`. Published only the existing PR #48 branch and
  updated its body. Hosted CI `37600117584` is running, with Linux job
  `112722153900` and Darwin job `112722154338`. Earlier failures and the
  protected-baseline exception remain recorded. This local publication record
  does not change the published source while those checks run.
- 2026-10-07: The current Darwin job is terminal cancelled, not a pass. Its
  authoritative timestamps span 1824 seconds and match the workflow's
  30-minute job guard. The separate bundle passes all 42 cases in 376.21
  seconds before the later complete recipe is cancelled. Linux passes.
  PR #47 has merged normally as `2e01c49a`; PR #48 is retargeted to main.
  Their base trees are identical. No replacement native run exists at the
  unchanged head. Prepared the separate complete-job budget task before any
  workflow edit; individual suite budgets and approved source remain intact.

- 2026-10-07: The aggregate CI repair changes only the overall job guard to
  75 minutes. The declared sequential commands can use 3620 seconds; the old
  job limit allowed only 1800. All 26 bounded checks and 28 subtests pass,
  including actual Nix suite ownership and unchanged individual budgets.
  The negative oracle rejects the old guard. All 74 approved files remain
  unchanged. Original cancellation evidence is retained; a new hosted pass
  remains required before delivery.
