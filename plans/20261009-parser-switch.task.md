# Parser switch, step 2 of ADR 0007

Created 2026-10-09. Status: IN PROGRESS.
Specification: [ADR 0007](../docs/adr-0007-parser-library.md), "Step 2: the
switch", "Cleanup in step 2" and "Acceptance evidence", items 5 to 10.
Depends on step 1: [task](20261009-parser-library.task.md), PR #71. This work
is stacked on the `tasks/parser-library` branch.

## Outcome

1. **The frontend parses through the library.** `belay.sqlite` has a `ctypes`
   binding that loads the library once per process from an explicit path,
   refuses another `api`, holds its own lock for each call, and passes the
   caller's `bytes` directly. `sql_tree.parse` takes a loaded library and a
   grammar identity instead of an executable path. It keeps its node checks
   and also checks that `grammar` equals the requested identity. The
   temporary-file snapshot, the process start, the 5-second deadline and the
   "SQL parser exceeded its time limit" rejection are gone.
2. **Profiles select a dialect.** A helper resolves a profile (release,
   SQLite source id, compile options) to a grammar identity in the four steps
   of the ADR, and rejects an unknown release, another source id, or grammar
   options without a built dialect, with a message that names the release,
   the options and the dialects. It ignores compile options that are not
   grammar options. The supported profiles stay the explicit list in
   `belay/sqlite/profiles.py`, which now also records each profile's SQLite
   source id. When the library loads, each supported profile must resolve to a
   built dialect. `verify` uses the default dialect of its release.
3. **The verifier runtime uses the library.** `Runtime.locate` returns the
   installed library path. The runtime package and the release archive
   contain the library instead of the executables. The installer tests pass
   and show that no ambient tool or library is used.
4. **The conformance harness parses each case with its recorded dialect,
   before the model check.** A case whose recorded profile has no built
   dialect is `MODEL_UNSUPPORTED` with the reason "no parser for this
   dialect", and the progress report counts these cases separately. A parser
   rejection of a statement that native SQLite ran is a harness error. The
   progress report binds the digest of the library instead of the executable.
5. **The executables are gone.** No file outside reports, plans and ADRs names
   `sqlite-parser` or `sqlite-parser-3.46.0`. The `just parser` recipe, the
   `build/` links, the `parsers` attribute's executables, the command-line
   part of `parser/main.c` and the step 1 comparison test are removed. No test
   starts a parser process.
6. **Documentation**: `docs/sqlite-parser.md` describes the library, the API,
   the metadata and the dialect table; `docs/trust-boundary.md` says that the
   parser runs inside the verifier process without a deadline;
   `docs/conformance-fixtures.md` no longer names the executables.

## Tests

- Binding: loading, `api` refusal, the unknown-grammar error, the `grammar`
  check, the resource limit and invalid input results, and the lock.
- Profile resolution: the expected dialect for each current profile; refusal
  of an unknown release, another source id and grammar options without a
  built dialect; compile options that are not grammar options are ignored;
  every supported profile resolves when the library loads.
- `tests/parser_test.py` runs through the binding and takes the grammars and
  dialects from the metadata, with result statuses instead of exit codes.
- The verifier, CLI, bundle and installed-runtime suites pass with the library.
- Conformance: each case of every retained corpus is parsed with the dialect of
  its recorded profile, including cases that the model check rejects later;
  no statement that native SQLite ran is rejected by the parser; cases without
  a built dialect are counted separately.
- A test run of the conformance files with a process counter starts no parser
  process.
- Evidence in the status file: the time of `parse` over the corpus v5
  migrations, before and after; the parser starts in the conformance test
  files before and after.

## Relevant source and constraints

- Frontend: `belay/sqlite/sql_tree.py::parse`, `belay/sqlite/profiles.py`.
  Callers: `migration_check/inputs.py`, `migration_check/runtime.py`
  (`Runtime.locate`, `Runtime.parser`), and through `Runtime.locate` the CLI,
  `prepare` and `bundle`.
- Harness: the parser path is built as `runtime / "build/sqlite-parser"` in
  `corpus.py`, `model_check.py`, `state_machine.py`, `measure_native.py` and
  `measure_coverage.py`, and passed as `parser` through `native_replay.py`,
  `native_trace.py` and `generated_program.py`. `native_fixture.py` runs the
  executable directly. `native_trace.read_schema` caches on the executable's
  inode and mtime; the cache key must change.
- `native_replay.model_case` raises `UNSUPPORTED` for `nativeVersion` 4
  records (corpora v4 and v5) before it parses. The ADR moves the parse before
  that check. Corpora v1 to v3 record `sourceId` but no profile object; their
  dialect is the default dialect of their recorded release.
- `progress.py` binds `RUNTIME_FILES` by digest, and
  `replay_tiers.runtime_binding` binds the parser path and digest. Old progress
  reports keep their executable digests: retained reports are evidence and
  stay unchanged.
- `tests/conformance_coverage_test.py` injects the timeout message to test
  `HARNESS_ERROR`; the timeout part goes, the broken-parser part stays.
- The library has no parse deadline and no crash containment (ADR,
  "Consequences").
- The suite input lists in `build-support/tests.nix` and the invalidation
  table in `tests/test_nix_test_targets.py` follow the moved inputs.
