# Hosted macOS model-suite timeout

Status: IN PROGRESS. Created 2026-10-06.

## Outcome

The hosted macOS model-suite timeout has an evidence-based cause and a bounded
complete verification path. The record compares actual hosted PR #43, PR #44,
main and passing PR #47 jobs, their exact source/runtime inputs, cache behavior,
commands, deadlines and test progress. A timeout remains a failed check.

A necessary change preserves every accepted test and generated case. Suite
decomposition retains complete ownership and configured subprocess deadlines;
a deadline change states the measured work that requires it. The smallest
meaningful checks verify the changed behavior and reject omitted coverage.
No native performance rerun starts while the existing host leases are reserved.

The temporary T03 acceptance record distinguishes passing hosted Linux and
retained local Darwin evidence from the outstanding hosted macOS model result.
Frozen PR #43, #44, #47 and #48 branches are unchanged. This task starts from
public main `29d2ed7ab7621373e5bb33c97ce8c325fad1b41f` in a separate workspace.

## Verification and constraints

Retained original hosted logs identify the failing command and last completed
case, with exact job/source identities. Pure routing, test ownership and Nix
evaluation checks verify any decomposition without expensive suite execution.
An eventual hosted model check must complete its accepted cases before this
task can claim the timeout is resolved. Expensive native validation requires
coordination with the host owner first.

Relevant sources are `build-support/tests.nix`, `tests/nix_suites.json`,
`.github/workflows/ci.yml`, `tools/ci_checks.py`, `tests/conformance_model_test.py`
and the conformance runner/profile helpers. Model-target dependency identities,
pytest generation and cache hits can explain different hosted outcomes without
a semantic change. The PR #48 model fix is separate work and cannot be silently
mixed into this branch or used to claim an older failing job passed.
