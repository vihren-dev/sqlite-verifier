# Date and time functions, slice 6f of ADR 0012: status

Created 2026-10-17. Status: open.
Task: [20261017-date-functions.task.md](20261017-date-functions.task.md).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), Amendment 5, "Date and
time functions (slice 6f)", owner decisions 2, 3 and 8.

## Relevant files

- Clock text and substitution: `packages/belay-sqlite/Belay/Sqlite/ClockText.lean`,
  `ClockSubstitution.lean`, `StatementClock.lean`.
- Expressions: `Resolution/QueryForm.lean` (`Resolved.Expr`), `QueryEval.lean`,
  `Resolution/Calls.lean`, `Resolution/QueryExprs.lean`.
- Restrictions: `Resolution/Restrictions.lean`, `Resolution/RestrictionText.lean`.
- Conformance: `conformance/authored_clock.py` (the controlled clock in authored cases).

## Progress

- 2026-10-17: task and status files, stacked on #153 (slice 6e2, PR B).

## Remaining

- Implementation, full checks, review, CI time, pull request A; then pull request B
  (claim corpus 27, `mustAgree`).
