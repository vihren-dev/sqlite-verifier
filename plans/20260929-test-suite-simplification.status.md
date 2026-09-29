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
