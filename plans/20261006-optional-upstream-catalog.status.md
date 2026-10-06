# Optional upstream catalog tests status

Status: IN PROGRESS. Created 2026-10-06.

Task: [optional upstream catalog tests](20261006-optional-upstream-catalog.task.md).
Source: [issue #38](https://github.com/vihren-dev/sqlite-verifier/issues/38).

Relevant files: `tests/conformance_catalog_test.py`,
`conformance/upstream_catalog.py`, `build-support/tests.nix`,
`tests/nix_suites.json`, `tests/runtime_support.py`.

## Progress

- 2026-10-06: Confirmed the shared fixture indexes the environment variable
  directly. All three archive-dependent cases use it. The Nix upstream suite
  supplies the pinned archive and selects the module. Created the task record
  before code changes in an isolated workspace based on `4a425828`.

## Validation and review

Pending. The host Python has no pytest; the configured Nix environment and
cached pinned archive provide the authorized test prerequisites.
