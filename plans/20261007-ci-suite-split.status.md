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
- 2026-10-07: Split the `model` suite into `model` (8 files), `frozen` (10) and
  `harness` (13); `conformance_command_sources_test.py` now runs only in
  `upstream`. The conformance suites receive only the 12 frontend modules in
  `tests/conformance_frontend.json`; `tests/test_conformance_frontend.py` checks
  that list against the actual imports. Each Nix test has a 300-second limit
  (`pytest-timeout`); the suite limit is a 1200-second hang guard.
  `developmentTests` excludes `model` and `frozen`.
- 2026-10-07: CI routing. `tests/ci_scope.py` selects `docs`, `test`,
  `infrastructure`, `packaging` or `package`; `tools/ci_checks.py` maps each to
  `just` recipes. Pull requests run on Linux; the macOS job reports without
  checks. `main` pushes, tags, manual and nightly runs check both platforms.
- 2026-10-07: Local validation on macOS. All nine Nix suites pass in the
  sandbox (`nix-build -A tests`, 13.9 min sequentially): atuin 12, bundle 33,
  cli 13, frozen 145, harness 120, kernel 19, model 51, sample 12, upstream 76.
  The 481 Nix-owned test IDs are identical to the baseline. `just test-source`:
  337 passed. `just test-nix`: 86 passed, including the new invalidation table.
- 2026-10-07: Finding, outcome 4 blocked. GitHub holds one active cache entry:
  the Linux store, 5.8 GB. The repository limit is 10 GB, so the Linux and
  macOS stores evict each other, and a cache saved for each pull request push
  would evict the `main` entry. Saving on pull requests is not implemented;
  the owner decides between a smaller store, a binary cache or no change.
