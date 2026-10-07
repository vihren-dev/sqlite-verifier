# Complete Darwin CI with an isolated bundle phase

Status: IN PROGRESS. Created 2026-10-07.

## Outcome

Hosted Darwin CI completes the exact bundle gate before it starts the complete
Nix test or package recipe. The bundle gate cannot overlap model or upstream
test builders in that invocation. Every complete recipe still checks all seven
Nix targets and the existing source, infrastructure and installed gates.
Linux keeps its current schedule.

The bundle gate retains its four test files and all 42 cases. Its suite limit
remains 420 seconds. All six default targets, including bundle, retain 420
seconds; the full model retains 600 seconds. Source, profiles, protected baselines,
proof checking, export and trust rules retain their existing meaning.

A failed or timed-out bundle phase fails CI before the complete recipe starts.
CI retains the actual command, elapsed time, exit status and original streams.
A successful Nix bundle output and its JUnit report use the existing artifact
retention paths. Receipt validity, a local pass and a hosted pass remain distinct.
The task requires successful complete hosted gates on both native platforms.

## Acceptance

Bounded scheduling checks verify Darwin's order for both complete scopes and
both existing modes. They verify the exact bundle attribute, sandbox flags,
artifact link and outer deadline, and retain the complete recipe afterward.
Linux checks verify that the added phase is absent. Failure and timeout checks
verify that CI stops, reports the actual failure and retains command artifacts.
Existing rendered Nix-command checks verify the unchanged membership and suite
limits. The full hosted gates verify the assembled behavior after publication.

The isolated receipt binds the exact failed PR47 derivation, runtime and test
inputs, all 42 original JUnit cases, original streams and before/after identities.
The two earlier hosted failures remain failures in the record. Historical
receipts and frozen v1–v5 corpus bytes remain unchanged.

## Constraints

`tools/ci_checks.py::run_checks` controls sequential host phases.
`build-support/tests.nix` and `tests/nix_suites.json` define suite membership and
limits. `just test-full` and `just package` retain the complete recipes.
`.github/workflows/ci.yml` retains `build/nix-tests*` outputs and
`build/ci-phases*` diagnostics.

PR47 head `555b9a74` and PR48 head `8e10a593` exhausted the whole Darwin bundle
budget while the first stage-reuse case was active. The exact PR47 derivation
then passed all 42 cases in an isolated local build under the same budget.
This supports a scheduling correction but does not establish the cause of
hosted contention. The correction does not add a dependency between Nix
derivations, change global job parallelism or infer a passing hosted gate.
