# Test suite simplification status

Created 2026-09-29. Status: DONE.
Task: [test suite simplification](20260929-test-suite-simplification.task.md).
Related: [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md),
[CI](../docs/ci.md), [build support](../build-support/README.md).

Relevant sources: `justfile`, `conftest.py`, `pytest.ini`, `tests/`,
`build-support/tests.nix`, `tools/ci_checks.py`, `tests/ci_scope.py`,
`.github/workflows/`, `conformance/`.

## Progress log

- 2026-09-29: Task and status created after the owner's decisions.
- 2026-09-29: Baseline host run (pre-change): 286 passed, 2 failed in 186s.
  `docs_test` fails on broken links in unrelated uncommitted draft docs
  (docs/0003, ADR-002, ADR-003 drafts in the working-copy parent); this stays
  a known pre-existing failure.
- 2026-09-29: Removed ADR-0001 benchmark tools, workflows, disk action,
  `tools/cache_fingerprint.py`, `tests/case-inventory.json` and their tests;
  dropped stale CI-scope entries. 299 cases collect; CI-scope tests pass.
- 2026-09-29: Replaced the custom reporting layer with plain pytest (removed
  `tests/case_reports.py`, `tests/catalogue.py`, catalogue/suite/run-id/report
  options, per-case artifacts and receipts; `--junitxml` in recipes and Nix
  targets; `just test-list` uses `--collect-only`). `run_command` kills the
  process group only; removed `tests/test_timeout_cleanup.py`, merged runtime
  selection cases into `tests/test_pytest_harness.py`. Axiom audit now returns
  problems and has a negative unit test. Host: 237 passed, 1 known docs
  failure (161s). Nix: atuin 16, kernel 19, model 6 passed.
- 2026-09-29: Converted the unittest-style test files (except
  `tests/test_ci_scope.py`, run by CI with stdlib unittest) to pytest; added a
  lazily importing `parse_sql` fixture and `tests/sql_fixtures.py`, removing
  the module-global `PARSER`/`ROOT` rebinding and all test-to-test imports. Link
  checking tests moved to `tests/docs_test.py`, which now asserts and exits
  nonzero as a script. Removed the duplicated profile-equality test (kept in
  `schema_generation_test.py`, now also asserting the 3.51 constructor).
  Literal comparison against the originals found one transcription error
  (missing `sqlite.nix`), fixed. Converted files: 120 passed; Nix targets pass.
- 2026-09-29: Removed tests that could not fail: constant status fields
  (`*_status`) from conformance reports, the upstream fixture and its schema,
  and the assertions on them; re-read coverage numbers; `atuin_sql_test.py`
  with its conformance helpers and the smoke-test nullable ADD (both only
  observed SQLite itself). The installed GC-root case now checks the root
  resolves to the runtime store path and is registered with Nix. Installed
  acceptance (existing archive): 6 passed. Nix: atuin 13, model 6 passed;
  kernel reused from cache.
- 2026-09-29: De-duplicated end-to-end cases. `cli_test.py`: removed
  `sorry`/unapproved-axiom/forged-`Generated` (covered by `kernel_gate_test.py`),
  schema/transitive drift (covered by `early_baseline_test.py` and Atuin), the
  `-- no-transaction` comment case (covered by `test_profiles.py`) and the
  `baseline` fixture's extra verification (the reverse-order case now uses the
  checked-in `examples/approved/baseline.json`); the helper case now asserts
  the recorded input. 13 passed in 49s (was ~97s). Atuin: dropped its `sorry`
  case and merged transitive-mapping drift into the parametrized drift case;
  Nix atuin target 12 passed.
- 2026-09-29: `just test` builds the Nix test targets once (dropped the
  equivalent `nix flake check` pass) and excludes `requires_nix` cases; new
  `just test-nix` runs them and `just package` depends on it. `cli_test.py` is
  a cached Nix target (`tests.cli`); CI routes the Nix infrastructure test files
  to packaging. `just test`: Nix targets pass (cli 13), host 259 passed plus
  the known draft-docs failure in 30s (was ~186s). `just test-nix`: 49 passed
  in 40s.
- 2026-09-29: Updated README, CI and build-support docs and recorded the
  owner's decisions in ADR 0001. Installed acceptance step of
  `just runtime-package` against the existing (unchanged-runtime) archive:
  18 passed. A fresh archive build was not run; the runtime inputs did not
  change in this task.

## Outcome (DONE)

- Host `just test` pytest step: ~186s → 30s; `cli_test.py` 97s → 49s and now
  cached in Nix; Atuin 16 → 12 cases.
- Known remaining failure: `tests/docs_test.py::test_local_markdown_links`
  reports broken links in the unrelated uncommitted drafts
  (`docs/0003-component-research.md`, `docs/adr-0002-compile-project-cache.md`).
- Not changed: the 2000-column model case (only check of column-limit error
  precedence against native SQLite); the pinned SQLite 3.46.0 binary, now only
  used by the smoke identity check.
