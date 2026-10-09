# Status: parser switch, step 2 of ADR 0007

Created 2026-10-09. Status: IN PROGRESS.
Task: [task](20261009-parser-switch.task.md).
Specification: [ADR 0007](../docs/adr-0007-parser-library.md).
Step 1: [status](20261009-parser-library.status.md), PR #71.

Relevant files: `belay/sqlite/sql_tree.py`, `belay/sqlite/profiles.py`,
`migration_check/runtime.py`, `migration_check/inputs.py`, `conformance/`
(`native_replay.py`, `native_trace.py`, `native_fixture.py`,
`generated_program.py`, `corpus.py`, `model_check.py`, `state_machine.py`,
`measure_native.py`, `measure_coverage.py`, `progress.py`, `replay_tiers.py`),
`build-support/runtime.nix`, `build-support/default.nix`, `justfile`, `parser/`.

## Findings

- The harness never selects a parser by version: it always uses
  `build/sqlite-parser` (3.51.0). `nativeVersion` 4 records (corpora v4, v5)
  become `MODEL_UNSUPPORTED` before any parse.

## Progress

- 2026-10-09: task and status files created in the jj workspace
  `parser-switch`, stacked on `tasks/parser-library`.

## Remaining

- Everything in the task file.
