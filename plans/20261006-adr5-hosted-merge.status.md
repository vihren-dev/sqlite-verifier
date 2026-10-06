# ADR 0005 hosted validation and merge status

Created 2026-10-06. Status: IN PROGRESS.
Task: [hosted validation and merge](20261006-adr5-hosted-merge.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

The owner approved the completed review repairs, conditional on successful
hosted CI on ubuntu-22.04 and macos-14 before merging. The existing local work
and scope remain approved. Publication, hosted checks, merge and follow-up
issues are pending. The owner also requested recording retention of the
independent SQLite 3.53.4 native pin in the ADR.

## Progress

- 2026-10-06: Read the owner review, existing CI routes, completed v5 evidence
  and workspace process. Prepared this task/status pair before publication or
  any necessary hosted correction. Read-only checks inspect CI scope and draft
  the six requested follow-up issues. No retries or semantic changes are planned.

- 2026-10-06: Recorded the owner's decision to retain the independent 3.53.4
  native pin, while keeping the production proof and model scope separate.
  Markdown links pass. Existing CI selects the complete packaging route on both
  approved hosted runners, including the v5 sample and full model target. The
  branch has no existing PR, and no open issue duplicates the six requested
  follow-ups. Main remains `31848aac`; the existing branch-start commit
  `2839c93c` is empty and has no description. Publication retains its original
  identity rather than rewriting source-bound evidence.
