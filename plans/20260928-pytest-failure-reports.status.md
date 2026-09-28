# Pytest outer failure reporting

Created: 2026-09-28. Status: DONE (bounded Darwin implementation and independent review).

Bounded follow-up to [the accepted pytest/Nix task](20260928-pytest-nix-builds.task.md)
and [ADR 0001](../docs/adr-0001-pytest-and-nix-ci.md), based on `ffc49c06`.
Author: formal_preservation. Independent reviewer: adr1_inventory; root integrates.

The final audit found that an outer suite watchdog can terminate pytest before
its session-finish report hook. The suite runner now removes prior known JSON and
JUnit outputs before launch and writes an honest suite-level failure when the
watchdog fires or either report is absent, including a zero-exit child with missing
reports. The envelope records source/run identity, exact requested selection,
unavailable case phases, timing and command artifacts. JUnit labels one runner
error; it does not invent per-case outcomes. Any current partial pytest report is
retained beside the command before replacement. Installed reports are separate.
The source, smoke and installed-package entrypoints share this watchdog; smoke's
15-second and installed-package's 1800-second limits remain unchanged. The helper
CLI forwards the actual archive without adding a runtime root or a build.

One execution-only checkpoint retains the collected identities in the existing
artifact digest layout, including runtime, suite and UUID. Catalogue-only calls
remain write-free except their requested catalogue. Fallback validates checkpoint
provenance and exact IDs when the caller supplied them; malformed bytes survive
for diagnosis and cannot provide case outcomes. Suite command artifacts now live
under the uploaded test-results tree; CI also retains the whole test-logs directory
so collection and coverage command diagnostics survive failures.

The source orchestrator always reaches current-run coverage aggregation after
collection, cache or suite failures, retaining original diagnostics and command
artifacts. Aggregator failure itself produces current-run failing coverage JSON.
No proof acceptance, cache acceptance, production timeout or ordinary pytest phase
reporting changes.

Actual-child regressions cover outer timeout, timeout after a partial report,
successful child missing its report, early collection failure/timeout, cache
rejection, simultaneous collection/aggregation failure, and installed-mode nested
process cleanup with the poisoned environment. Five resource-free cases separately
reject invalid runtime, suite, run, selected IDs and malformed checkpoint bytes.

After `python3 tools/check_resources.py`, one persistent `nix develop path:./nix`
shell supplied Python 3.14.7 / pytest 9.1.1. Final checks:

- `python3 -m pytest tests/test_suite_failure_reports.py tests/test_source_runner.py
  tests/test_independent_suites.py tests/test_pytest_harness.py
  tests/test_runtime_selection.py tests/test_source_orchestration.py
  tests/test_coverage_receipts.py -q --suite failure-report-routes`: 62 passed,
  two subtests passed in 24.23s.
- `python3 -m pytest tests/test_suite_checkpoints.py -q --suite checkpoint-validation`:
  five passed in 0.11s.
- Both new modules collect 13 IDs into `build/failure-report-catalogue.json`.
  Every ID passed in a separate pytest invocation (16.64s combined process time),
  then all passed reversed (13.85s pytest / 14.02s process time). Bounded command
  observations and timing summary are in `build/failure-order/`.
- `just --dry-run smoke runtime-package` preserves the intended selectors,
  deadlines, archive argument, packaging resource guard and bare interpreter.
- `SQLITE_VERIFIER_RUNTIME_ROOT=/nix/store/00b6q3j0lwsh55597prmyv63awq5bsff-sqlite-verifier-runtime-1
  just smoke`: all five actual toolchain/native cases passed via the helper CLI
  in 0.68s total. No native Lean or package build was performed.

Independent reviewer adr1_inventory approved the implementation, installed-route
extension, actual-child regressions and checkpoint validation. Reviewer requested
three-second synthetic timeout bounds (normal 30-second bounds for other cases)
to avoid making negative fixtures depend on one-second CI startup. The preserved
partial report is checked for its observed setup outcome and duration. Inventory
integration remains owned by the lead/member to avoid concurrent edits; these
13 source-only additions bring the expected integrated catalogue to 422 identities.
Native CI and the overall ADR performance/rollout gates remain open.
