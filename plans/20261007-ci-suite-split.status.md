# Status: split the CI test suites by their real dependencies

Created 2026-10-07. Status: IN PROGRESS.
Task: [20261007-ci-suite-split.task.md](20261007-ci-suite-split.task.md).
Workspace: `ci-split` (`../sqlite-verifier-ci-split`), based on `main` at
`aeffab25`.

Relevant files: `.github/workflows/ci.yml`, `tests/ci_scope.py`,
`tools/ci_checks.py`, `build-support/tests.nix`, `build-support/default.nix`,
`tests/nix_suites.json`, `conftest.py`, `justfile`, `docs/ci.md`,
`tests/test_nix_test_targets.py`, `tests/test_test_ownership.py`.

## Baseline measurements (CI run 37587787077, `main`, 2026-10-07)

| Suite | Tests | macOS | Linux |
| --- | --- | --- | --- |
| atuin | 12 | 105 s | 160 s |
| bundle | 33 | 215 s | 249 s |
| cli | 13 | 41 s | 66 s |
| kernel | 19 | 49 s | 65 s |
| model | 323 | 295 s | 315 s |
| sample | 12 | 69 s | 109 s |
| upstream | 76 | 5 s | 11 s |
| host source tests | 329 | 28 s | 29 s |
| host `test-nix` | 81 | 110 s | 101 s |
| host installed | 21 | 183 s | 125 s |

Job wall time: 23.6 min on macOS, 17.2 min on Linux. Nix runs about three
suites at the same time. In 12 of 30 consecutive pull request pushes, the
push changed only `plans/`, `reviews/`, `reports/` or documentation.

## Progress

- 2026-10-07: Task and status files created.
