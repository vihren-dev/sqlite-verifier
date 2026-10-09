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
- With the step 1 library and each case's recorded release, the parser
  rejects 28 trace statements and 12 migrations across corpora v1 to v5. In
  each of them native SQLite also failed (`error` set, or last `primaryCode`
  1). No statement that native SQLite ran is rejected.

## Progress

- 2026-10-09: task and status files created in the jj workspace
  `parser-switch`, stacked on `tasks/parser-library`.
- 2026-10-09: binding (`belay/sqlite/parser_library.py`), dialect selection
  (`belay/sqlite/dialects.py`), source ids and `SUPPORTED_PROFILES` in
  `profiles.py`; the runtime and the conformance runtime contain the library
  at `lib/`, and `just build` links it. The executables still serve all
  callers. `just test-source` with the built runtime: 498 passed.
- 2026-10-09: switch. `sql_tree.parse` takes a `SqlParser` (library and
  grammar); the verifier selects the default dialect of its profile; the
  harness selects each case's dialect from its recorded profile
  (`conformance/record_parser.py`) and parses before the model check; the
  progress and tier reports bind the library's digest; `progress` reports
  `noParserForDialect` (0 for all retained corpora). Corpus v5 replay:
  4,376 `MODEL_UNSUPPORTED`, 0 harness errors. One case,
  `aggorderby:aggorderby-10.1:28`, has a 140 KB migration that exceeds the
  200,000-node limit; native SQLite refused it too, so a resource limit on a
  natively refused migration is now `MODEL_UNSUPPORTED`, as a syntax rejection
  was (`ParserResourceLimit`). `just test-source` with the built runtime: 460
  passed; all ten Nix suites pass; `tests/test_nix_test_targets.py`: 63
  passed. The executables are still built, but no caller uses them.

## Measurements (Linux amd64, local, 2026-10-09)

| Step | Executable | Library |
| --- | --- | --- |
| `parse` of all 4,376 corpus v5 migrations, through `sql_tree.parse` | 3.69 s | 1.30 s |

The ADR's 18.0 s and 1.8 s were measured on macOS arm64, where a process start
costs more.

## Remaining

- Everything in the task file.
