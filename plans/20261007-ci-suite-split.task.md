# Task: split the CI test suites by their real dependencies

Created 2026-10-07. Status: IN PROGRESS.
Status file: [20261007-ci-suite-split.status.md](20261007-ci-suite-split.status.md).

## Problem

A typical pull request runs for 15 to 23 minutes on two platforms. Most of
this time repeats checks whose inputs did not change:

- The `model` Nix suite has 323 tests in 32 files. One cache entry covers all
  of them, so a change to one small test file runs about 5 minutes of tests
  again.
- The conformance suites declare every `migration_check/*.py` file as an
  input. The conformance harness uses only the SQL frontend modules, so a
  change to `prepare.py` or `runtime.py` runs all conformance suites again.
- Pull request runs never save their results. A later push to the same pull
  request that changes only `plans/` or `reviews/` runs everything again.
- Nearly every pull request runs the Nix infrastructure tests and the
  installed-archive acceptance, which are never cached.
- Each Nix suite has one elapsed-time limit for the whole suite. Suites run
  in parallel, so on the 3-core macOS runner the result depends on which
  suites run at the same time.

## Owner decisions (2026-10-07)

- Pull request CI runs on Linux only. macOS runs on pushes to `main`, on
  release tags, on manual runs and on a nightly schedule.
- The installed-archive acceptance keeps all its cases. It runs when
  packaging inputs change, on pushes to `main`, on release tags, on manual
  runs and nightly.
- The development sample keeps its replay bound (ADR 0005 C7). It stays in
  its cached Nix suite.
- The Lean runtime split (a conformance runtime without the proof gates)
  belongs to the model package task (T10), not to this task.

## Required outcome

1. **Model suite split.** The current `model` suite becomes three Nix suites:
   - `model`: compiled model comparisons with native SQLite on authored and
     generated cases.
   - `frozen`: checks of frozen corpora (v1 to v5) and retained reports.
   - `harness`: fast acquisition, storage, profile and workload checks.

   Every test that runs today still runs in exactly one suite. A test file
   that is in two suites today is in one suite after the change.
2. **Narrow frontend inputs.** The conformance suites (`model`, `frozen`,
   `harness`, `sample`, `upstream`) declare only the `migration_check`
   modules that their tests import, directly or transitively. A change to an
   application module, for example `migration_check/prepare.py`, leaves these
   suites cached.
3. **Per-test time limits.** Each Nix suite applies a per-test time limit
   with `pytest-timeout`. A hung test fails with its own test name. The
   suite-level `timeout` remains as a guard against a hang outside a test.
4. **Results reused across pushes.** A pull request run saves its Nix store
   cache. A later push to the same pull request that changes only `plans/`
   or `reviews/` finds all Nix suites cached.
5. **Check selection.**
   - Pull requests run the Nix suites and the source tests on Linux. The
     macOS job reports success without running checks, so the required
     status check still reports.
   - The Nix infrastructure tests (`test-nix`) run when the build
     definitions or the shared test infrastructure change, and in full runs.
   - The installed-archive acceptance runs when packaging inputs change, and
     in full runs.
   - A full run (push to `main`, release tag, manual run, nightly schedule)
     runs every check on both platforms, as today.
   - A pull request that changes only Markdown documentation keeps the
     current `docs` scope.
6. **Documentation.** `docs/ci.md` describes the suites, the per-test limits,
   the check selection and the cache behavior.

## Tests that verify the outcome

- `tests/test_nix_test_targets.py`:
  - The suite set is exactly `atuin`, `bundle`, `cli`, `kernel`, `model`,
    `frozen`, `harness`, `sample` and `upstream`, and each suite command
    runs exactly the files in `tests/nix_suites.json` with the per-test
    limit.
  - The dependency invalidation table includes at least: a frozen corpus
    file changes `frozen` (and `sample` or `upstream` where they read it)
    but not `model` or `harness`; `migration_check/prepare.py` changes no
    conformance suite; `migration_check/translate.py` changes every suite
    that imports it; a test file changes only its own suite.
- `tests/test_test_ownership.py`: the union of all suite files and host
  test files is the complete test set, and no test file is in two Nix
  suites.
- A new source test checks that each conformance suite declares every
  `migration_check` module that its test files import transitively. A
  missing declaration fails on the host before Nix runs.
- `tests/test_ci_scope.py`: the check selection for docs-only, record-only,
  conformance-only, application, packaging, build-definition, `main` push,
  tag, manual and scheduled events.
- `tests/test_ci_checks.py`: the CI driver runs `test-nix` and the
  installed acceptance only when selected.
- Acceptance: `just test` and `just test-full` pass locally on macOS. The
  pull request CI passes on Linux, and a later push that changes only
  `plans/` finds every Nix suite in the cache. The list of test IDs from
  all suites and host runs is the same before and after the change.

## Tricky points

- `build-support/tests.nix` reads `tests/nix_suites.json` at evaluation
  time. `conftest.py` uses the same file to exclude delegated tests from
  host runs. Both must agree.
- `developmentTests` in `build-support/default.nix` removes `model` for
  `just test`. Decide which of the three new suites belong to the
  development run. The full `tests` set must keep all of them.
- The `upstream` suite and the `model` suite both run
  `conformance_command_sources_test.py` today.
- Most conformance test files import 40 or more harness modules
  transitively. Do not try to narrow the harness Python inputs per suite in
  this task; narrow only the frontend (`migration_check`) inputs.
- The Nix suites set `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1`. The timeout plugin
  must be loaded explicitly (`-p pytest_timeout`).
- The repository ruleset requires the checks `Check (x86_64-linux)` and
  `Check (aarch64-darwin)`. A matrix entry that does not exist reports
  nothing, and the pull request cannot merge. Keep the macOS matrix entry and
  skip its steps on pull requests.
- `nix-community/cache-nix-action` uses a primary key with `github.sha`
  today, so every run writes a new cache entry. Caches that a pull request
  saves are visible only to runs of that pull request, not to `main`.
- `tests/ci_scope.py` decides from the diff against the pull request base.
  Host checks must still run on the final head when an earlier push
  selected them; do not decide from the previous push only.
- Relevant files: `.github/workflows/ci.yml`, `tests/ci_scope.py`,
  `tools/ci_checks.py`, `build-support/tests.nix`, `build-support/default.nix`,
  `tests/nix_suites.json`, `conftest.py`, `justfile`, `docs/ci.md`,
  `nix/flake.nix`.
