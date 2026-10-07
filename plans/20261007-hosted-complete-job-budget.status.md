# Hosted complete-job budget status

Created 2026-10-07. Status: IN PROGRESS.
Task: [task](20261007-hosted-complete-job-budget.task.md).

The workflow's 30-minute job guard cancelled PR #48 Darwin job `112722154338`
after 1824 seconds. No replacement run exists at the same head. The bundle had
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
