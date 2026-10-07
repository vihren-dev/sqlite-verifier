# Complete hosted native jobs within their declared phase budgets

Created 2026-10-07. Status: IN PROGRESS.

## Outcome

The hosted complete native job can finish the existing sequential runtime,
Darwin bundle and complete-check phases without the job deadline cancelling a
phase whose own deadline has not expired. Its 75-minute overall guard covers
those declared budgets and at least five minutes for setup and artifact retention.
Both hosted platforms still perform their actual complete checks. A cancelled
or unfinished job remains incomplete.

Every individual suite, command, case and artifact remains selected. Runtime
builds retain 900 seconds, the Darwin bundle build retains 900 seconds and the
complete recipe retains 1800 seconds. Bundle and the other default suites retain
420 seconds; the model retains 600 seconds. Baselines, profiles, proof rules,
source identity and exporter semantics remain unchanged.

## Acceptance

Bounded tests exercise the real CI phase orchestration with short command
fixtures for both scopes, modes and native systems. The declared hosted budget
must cover all observed sequential phase limits plus the setup allowance. The
old 30-minute job guard fails that check. Existing scheduling and Nix ownership
checks retain suite membership and individual budgets. Current complete hosted
checks on both platforms must actually pass before delivery.

The original cancelled Darwin job remains retained with its timestamps, complete
bundle result and unfinished later phase. Historical local and hosted receipts
are not relabeled. Owner-approved baseline drift remains a separate exception.

## Relevant source and constraints

`.github/workflows/ci.yml` sets the overall hosted job deadline.
`tools/ci_checks.py::run_checks` supplies the sequential command budgets.
`justfile` and `build-support/tests.nix` retain individual recipe and suite bounds.
PR #48 run `37600117584`, Darwin job `112722154338`, ran for 1824 seconds before
cancellation. Its separate bundle passed all 42 tests in 376.21 seconds; the
complete job did not finish. This task changes only the aggregate job budget.
