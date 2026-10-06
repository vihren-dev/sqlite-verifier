# One SQL executor implementation status

Created 2026-10-06. Status: IN PROGRESS.
Task: [observable outcomes](20261006-single-sql-executor.task.md).
Sources: public issues #21 and #13.

## Current state

Investigation and task specification are complete. The dependency integration
combines the prepared T05 task with reviewed exporter `07dc71b3`, current main
`ba48d848` and checked declaration documentation `d01db1e6`. The first execution
proof migration is in progress. Final owner approval of the exporter and the T03
release remain separate gates.

Relevant definitions and callers are listed in the task file. The removed
executor's unconditional preservation law relied on treating data statements
as errors. Its replacement must state a schema-extension domain explicitly.
The generated starting-schema pattern already exists in the Atuin example.

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
acceptance or authorization to update approval. The full model gate is held
for the separate T13 test-environment feedback. Bounded compilation, source,
ordinary, affected model and installed checks can proceed; complete acceptance
still requires the full gate after that blocker is resolved.

Final owner review, ordinary and full checks, installed examples and issue
closure remain open. The task is not DONE.
