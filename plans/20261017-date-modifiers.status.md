# Date and time modifiers, slice 6g of ADR 0012: status

Created 2026-10-17. Status: open.
Task: [20261017-date-modifiers.task.md](20261017-date-modifiers.task.md).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), Amendment 5, "Date and
time modifiers (slice 6g)", owner decisions 3 and 6.

## Relevant files

- Date port: `packages/belay-sqlite/Belay/Sqlite/Date/` (`DateTime`, `Parse`,
  `Functions`).
- Resolution: `Resolution/Calls.lean` (`dateCall`), `Resolution/Restrictions.lean`.
- Profile scope: `conformance/profile_scope.py`, `conformance/execution_profile.py`.
- Cases: `conformance/authored_date_functions.py` (slice 6f).

## Progress

- 2026-10-17: task and status files, stacked on #155 (slice 6f, PR B).

## Remaining

- Implementation, full checks, review, CI time, pull request A; then pull request B
  (claim corpus 28, `mustAgree`).
