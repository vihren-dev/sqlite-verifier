# Test suite simplification status

Created 2026-09-29. Status: IN PROGRESS.
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
