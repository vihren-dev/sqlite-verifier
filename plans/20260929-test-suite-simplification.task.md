# Test suite simplification

Created 2026-09-29. Status: DONE.
Status file: [status](20260929-test-suite-simplification.status.md).

A review of the complete test suite (2026-09-29) found that most test code
checks test/CI/benchmark infrastructure rather than the verifier, that expensive
end-to-end cases repeat properties already checked at cheaper layers, that some
cases cannot fail, and that `just test` does redundant or misplaced work. The
owner decided (2026-09-29):

- delete the ADR-0001 rollout benchmark tooling;
- replace the custom pytest reporting layer with plain pytest;
- remove duplicated end-to-end cases, keeping each property at its cheapest
  faithful layer plus one end-to-end check (Atuin contract mutations stay);
- bound test-command timeouts by killing the child's process group only.

These decisions supersede the corresponding parts of
[ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md) (per-case receipts, separate
source/installed report trees, catalogue, benchmark rollout, "keep all Atuin
cases", descendant cleanup beyond the process group).

## Observable behavior when done

Running tests:

- `just test` builds each cached Nix pytest target once (no second, equivalent
  `nix flake check` pass) and keeps `build/nix-tests*` result links. The flake
  still exposes the same derivations as `checks.<system>`.
- `tests/cli_test.py` runs as a cached Nix pytest target like Atuin, not
  uncached on the host.
- Tests that exercise Nix itself (source identities, test-target invalidation,
  flake environment snapshot, installer from a local cache) do not run in
  `just test`; they run in `just package`, which CI selects for build, Nix,
  tooling and packaging changes, including changes to those test files.
- Host runs produce ordinary pytest output and JUnit XML via `--junitxml`; CI
  uploads that XML and the Nix test outputs.

Harness:

- No `--catalog`, `--catalog-json`, `--suite`, `--run-id` or `--report-dir`
  options, no per-case artifact directories or JSON receipts, no mandatory
  level-marker/docstring validation. `pytest --collect-only` lists cases.
  Markers remain registered for `-m` selection. `--runtime-root`,
  `--runtime-archive` and `--runtime-variant` keep their meaning, and selected
  missing prerequisites still fail setup instead of skipping.
- `run_command` kills the child's whole process group on timeout, reaps it and
  raises with partial output. No `ps`-based descendant discovery remains.
- Test modules do not import from other test modules; shared helpers live in
  non-test support modules. Python tests are plain pytest functions, except
  `tests/test_ci_scope.py`, which CI's docs-only route runs with stdlib
  `unittest` outside Nix.

Removed:

- `tools/benchmark_*.py`, `tools/cache_fingerprint.py`, benchmark workflows
  and action, `tests/case-inventory.json`, and their tests.
- Assertions on constant placeholder strings (`NOT_YET_*`,
  `NOT_COMPARED_BY_THIS_TEST`) and the placeholders themselves; coverage
  numbers re-read from the fixture they were generated from.
- Tests that only check native SQLite's own behavior (`atuin_sql_test.py`,
  the smoke-test nullable ADD) and their helpers; `test_proof_build` (implied by
  every Lean test) and the unread coverage receipt files.
- End-to-end duplicates: `sorry`/unapproved-axiom/forged-`Generated` rejection
  in `cli_test.py`, Atuin's `sorry` case, `cli_test.py` baseline-drift cases
  covered by `early_baseline_test.py`, and the duplicated profile-equality test.
- `cli_test.py` no longer runs an extra complete verification only to obtain a
  baseline manifest.

Strengthened:

- The installed-runtime GC-root case checks that the root actually retains the
  installed runtime; the installer URI case is named for what it proves.
- The docs link check fails through an assertion (and a nonzero exit when run
  as a script).
- `tests/ci_scope.py` has no stale file entries and routes the Nix
  infrastructure test files to packaging.

## Test suite that verifies it

- Host suite: every remaining host case passes via the `just test` pytest step.
- Nix targets `kernel`, `model`, `atuin` and `cli` build with sandbox enabled.
- `tests/test_nix_test_targets.py` asserts the new target set (including
  `cli`), the dependency-invalidation matrix and flake/legacy equivalence.
- `tests/test_pytest_harness.py` covers: missing prerequisites fail setup,
  installed variant cannot fall back to host Lean, archive option conflicts,
  private writable example copies, JSON diagnostics, and a process-group
  timeout that kills a grandchild and keeps partial output.
- `tests/test_ci_scope.py` covers routing of the Nix infrastructure tests.
- `just package` on the local platform runs the Nix infrastructure tests and
  installed acceptance.

## Tricky points

- `nix-build -A tests` is still needed for result links (Nix 2.18's
  `flake check` cannot create them); `test_flake_checks_reuse_existing_targets`
  keeps both entrypoints equivalent.
- Unittest-style files use an autouse fixture that rebinds module globals
  (`PARSER`, `ROOT`); converting them must keep parsing against the selected
  `--runtime-root`, not the checkout.
- `tests.nix` source filesets list shared support files explicitly; removing
  `tests/case_reports.py`/`tests/catalogue.py` and adding a `cli` suite changes
  derivation inputs and the invalidation expectations.
- `tools/ci_checks.py` imports `run_command`; its phase records must still be
  written after the simplification.
- `migration_check/process.py` already starts its own session; after the change
  an outer test timeout will not reach it, but its own deadline still applies.
- The working-copy parent holds unrelated draft docs with broken links; the
  repository docs check reports them. They are not part of this task.
- The 2000-column model case stays: it is the only check of the column-limit
  error precedence against native SQLite.
