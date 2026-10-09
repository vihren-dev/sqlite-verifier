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

- 2026-10-09: review `20261009T145904Z-ee5bde65`: findings 1 and 2 are R8
  owner-review markers on `migration_check/bundle.py` and `prepare.py`, whose
  only change is that `Runtime.locate()` has no parser-version argument;
  deferred to the owner. Findings 3 to 6 fixed in `cfe5c47b`; its review's two
  findings fixed in `7b395f55` (review with no findings).
- 2026-10-09: removal. The `parsers` derivation, `sources.parsers`,
  `parser/main.c`, `just parser`, the `build/` links, the CI cache root, the
  step 1 comparison test and `test_grammar_inventory` (replaced by the build's
  production-count step) are gone; `generate.py` requires a Lemon prefix. The
  runtime and conformance roots have no `build/` directory, and no file outside
  reports, plans and ADRs names the executables, so no test can start a parser
  process. `docs/sqlite-parser.md`, `docs/trust-boundary.md`,
  `docs/conformance-fixtures.md`, `docs/ci.md` and `build-support/README.md`
  describe the library. `tests/test_source_identity.py` gives its synthetic
  tree the inputs that Nix evaluates for the parser library. `just test-source`
  with the built runtime: 459 passed; all ten Nix suites pass;
  `tests/test_nix_test_targets.py` and `tests/test_source_identity.py`: 112
  passed.

## Measurements (Linux amd64, local, 2026-10-09)

| Step | Executable | Library |
| --- | --- | --- |
| `parse` of all 4,376 corpus v5 migrations, through `sql_tree.parse` | 3.69 s | 1.30 s |

The ADR's 18.0 s and 1.8 s were measured on macOS arm64, where a process start
costs more.

## Remaining

- Owner review of the R8 markers (`Runtime.locate()` in `bundle.py` and
  `prepare.py`).
- Installer tests with a built archive (`just runtime-package`), and the macOS
  arm64 runs of the load test and the installer tests.
