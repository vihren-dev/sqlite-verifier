# One SQL executor implementation status

Created 2026-10-06. Status: IN PROGRESS.
Task: [observable outcomes](20261006-single-sql-executor.task.md).
Sources: public issues #21 and #13.

## Current state

Investigation and task specification are complete. The dependency integration
combines the prepared T05 task with reviewed exporter `07dc71b3`, current main
`ba48d848` and checked declaration documentation `d01db1e6`. Executable feature
work has not started. Final owner approval of the exporter and the T03 release
remain separate gates.

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
