# Hosted complete-job budget status

Created 2026-10-07. Status: IN PROGRESS.
Task: [task](20261007-hosted-complete-job-budget.task.md).

PR #48 Darwin job `112722154338` was cancelled after 1824 seconds, matching
the configured 30-minute job guard. No replacement run exists at the same head. The bundle had
already passed 42 tests in 376.21 seconds. Its later complete recipe remained
unfinished. Linux passed; neither result supplies a complete Darwin pass.

The configured sequential phase limits total at most 3620 seconds in build
mode on Darwin, including both version commands. The existing 30-minute job
limit is shorter than that total. The proposed 75-minute guard covers those
limits and a five-minute setup and artifact allowance. Every inner bound and
test selection remains intact.

Original job metadata is retained in `build/t05-hosted-job-budget/darwin-job.json`.
The decoded job log will be retained beside it. This planning checkpoint makes
no workflow change and claims no new hosted acceptance.

Decisions waiting for the owner:

- None for this CI repair. The exact proposed baseline drift is already approved.

The workflow now has a 75-minute overall limit. All 26 focused orchestration,
scheduling, failure retention, routing, documentation and actual Nix-command
ownership checks pass, with 28 subtests, in 3.91 seconds under 120 seconds.
The actual phase-budget test rejects the original 30-minute guard without
changing the repository. All 74 owner-approved source, pin and baseline files
remain unchanged. Original job metadata, console bytes and the negative
oracle are retained in [the report](../reports/20261007-hosted-complete-job-budget/README.md).
Independent review and new hosted acceptance remain pending.

Review `20261007T112717Z-91635dcd` returned zero must findings and two
suggestions. Updated the CI guide to the actual 75-minute job limit and
named the five-minute setup/artifact allowance in its test. Both suggestions
are recorded as fixed. The same 26 tests and 28 subtests pass after these
corrections; no individual deadline or approved source changes.
