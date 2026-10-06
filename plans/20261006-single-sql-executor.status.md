# One SQL executor implementation status

Created 2026-10-06. Status: IN PROGRESS.
Task: [observable outcomes](20261006-single-sql-executor.task.md).
Sources: public issues #21 and #13.

## Current state

The executor implementation and prior native ordinary/installed acceptances are
retained, but complete acceptance fails: hosted CI exposed a mutation-harness
boundary bug on both supported platforms. The requested correction is in progress. Integration includes reviewed
exporter `07dc71b3`, checked root documentation `db69c816` and main `29d2ed7a`.
Full model acceptance must now run locally on both Darwin and Linux after the
requested correction; earlier short checks do not replace it. Final
owner review of the changed target file and proposed baselines remains pending.
The exporter owner approval and T03 release remain separate gates. This task is
not DONE while those required T05 acceptance gates are open.

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

## Exporter checkpoints and remaining gates

The T03 and T02 receipts describe a fixed model and input checkpoint. Their
source hashes, native bundle bytes, helper bytes and JUnit receipts remain
immutable. T05 intentionally changes current proof APIs and approved inputs.
Its live regression must record the current input and library identities,
check bundle trust bindings, reproduce deterministic preparation and independently
verify the current success, checked refutation and Atuin cases. It does not
compare changed inputs with the old checkpoint or add an old-runtime path.

The protected-baseline CI guard remains unchanged. Proposed schema bindings
require final owner review; the expected baseline drift failure is not proof
acceptance or authorization to update approval. Earlier bounded work held the
full gate for T13 feedback. The latest owner review now requires the complete
local model suite on both Darwin and Linux after the mutation-harness correction,
with the existing suite bounds and every model case retained. Passing targeted
checks does not supply that full acceptance.

Final owner review, full model acceptance and hosted integration checks remain
open. Native ordinary and installed checks are complete. Issue closure remains
with the owner. The task is not DONE.
