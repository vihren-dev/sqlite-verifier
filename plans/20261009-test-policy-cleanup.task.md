# Remove tests of dependency behavior

Created 2026-10-09. Status: IN PROGRESS.
Rules: "Testing" in [AGENTS.md](../AGENTS.md) and review condition R15.
Owner request: remove or reduce the tests that the review of 2026-10-09 found
outside these rules.

## Outcome

The test suite no longer asserts SQLite's or Lean's own behavior where no
problem of that dependency is suspected. The authored corpus cases stay
unchanged: fresh native replay and the model comparison keep using SQLite as
the oracle. Only hand-written restatements of SQLite's results go.

1. `tests/conformance_authored_queries_test.py`: the tests of aggregate, join,
   CAST and JSON results are removed. The tests of our tie groups and our clock
   stay.
2. `tests/conformance_authored_boundaries_test.py`: the tests of SQLite's
   default affinity, `ADD ... NOT NULL` rules, rejected `ADD` forms and the
   definitions that SQLite accepts or rejects are removed. The catalog,
   transport and model-refusal tests stay.
3. `tests/conformance_authored_test.py`: the tests of defaults, UPSERT and
   RETURNING, constraint failures and trigger/cascade counts are removed. The
   last one duplicates `test_record_outputs_and_direct_changes` in
   `tests/conformance_record_test.py`. The catalog, evidence and binding tests
   stay.
4. `tests/conformance_authored_review_test.py`: the CAST test is removed. The
   deferred foreign-key test keeps only the checks of our observer: the open
   transaction and the separate visible and persisted snapshots.
5. `tests/conformance_authored_transactions_test.py`: the tests of ROLLBACK,
   SAVEPOINT and first-failure semantics are removed. One test keeps the checks
   of our observer for a committed group; the catalog test stays.
6. `tests/test_checked_public_docs.py` is removed. It checks Lean's Verso
   documentation checks, with a probe that sets the option itself.
7. `tests/conformance_dqs_test.py`: the assertions of SQLite's double-quoted
   string fallback are removed. The check that both pinned libraries use the
   default DQS configuration stays, now with the compile-option check.
   `test_connection_dqs_profile` in `tests/conformance_pipeline_test.py`, which
   repeated the same configuration check and SQLite quirk, is removed.
8. The module docstring of `tests/test_toolchain_smoke.py` names only what it
   checks: the pinned tool identities.

## Tests

- Every remaining test passes, in the source suite and in the Nix suites that
  own the changed files.
- Each removed test is listed in the status file with the reason, and with the
  remaining test that covers our part of it, if any.
- `tests/nix_suites.json`, `tests/conformance_frontend.json` and the test
  ownership tests stay consistent after the file removal.

## Relevant source and constraints

- The authored records come from frozen evidence; `native_replay` replays them
  against SQLite, and the model comparison classifies them. These checks stay.
- `conformance/native_connection.py` already refuses a connection whose DQS
  configuration differs from the library default.
- Helpers and imports that only the removed tests use are removed too.
