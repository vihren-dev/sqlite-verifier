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
- 2026-10-07: Owner chose to shrink the cache. Measurement on macOS: the
  closure that one commit needs (outputs of the test targets, runtimes,
  parsers, dev shell and their build inputs) is 131 paths, 5.15 GB
  uncompressed and 1.34 GB with zstd. The 5.8 GB Linux cache therefore holds
  mostly outputs of older commits. `tools/ci_store_gc.py` roots the current
  closure and collects the rest before the save; the cache key now ignores
  `plans/` and `reviews/`, and every run saves, so outcome 4 is back in scope.
  Root registration was checked locally without collecting; collection itself
  can be checked only in CI.
- 2026-10-07: Review tooling. `just review` failed twice (exit 3) because Codex
  refuses to run without a `.git` directory, which secondary jj workspaces lack.
  Fix `0d8cf966` passes `--skip-git-repo-check`; its review passed. Review of
  `437ce97c` found one must (package submodule imports skipped by the frontend
  check) and three shoulds; all fixed in `023d9df8`, whose review passed.
- 2026-10-07: Review of `d3d84c15`: no must; named the garbage-collection
  timeouts and reported the failed command's diagnostic (fixed). Deferred: the
  `nix-tests-v1` restore prefix stays until both platforms have saved `v2`
  caches, so the first run does not start from an empty store; then remove it.
- 2026-10-07: Draft PR #52. First CI run (37602407809, full `package` scope on
  Linux because the workflow changed): Linux passed in 14.6 min; the macOS job
  reported success in 5 s without checks. It restored the 6.1 GB `v1` cache;
  garbage collection took 5 s, and the saved `v2` cache is 3.2 GB.
- 2026-10-07: `main` gained PR #47, whose Darwin bundle-first CI step and
  bundle inputs conflicted with this branch. Merged `main`: kept the Darwin
  bundle prebuild, combined it with the scope recipes, and updated its text
  for the per-test limits. Local macOS checks after the merge: all nine suites
  pass (bundle now 42 tests), `just test-source` and `just test-nix` (86) pass.
  The record-only push `0d42c506` started no CI run because the pull request
  had a merge conflict; the cache-reuse check is repeated after this merge.
