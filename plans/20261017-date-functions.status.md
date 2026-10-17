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
- 2026-10-17: implementation of pull request A.
  - Port of SQLite 3.51.0's `date.c` without modifiers, under `Belay/Sqlite/Date/`
    (`DateTime`, `Parse`, `Printf`, `Strftime`, `Functions`, and 141 checked examples):
    200,000 differential cases against native SQLite under the controlled clock, 0
    mismatches. Not modeled: SQLite's `string or blob too big` for a `strftime` result
    over the length limit.
  - `Resolved.Expr.date function arguments clock`: resolution stores clock 0, and
    `Expr.atClock` sets the statement's clock value on each call that may read `now`
    (`DateFunction.readsNow`: no time value, or one that is not a literal other than
    `now`, `subsec` or `subsecond`).
  - `Syntax.Expr.callEmpty` for a call without arguments, such as `date()`; other names
    stay `unmodeled-function`. The new restriction `date-modifier` refuses modifiers.
  - Authored cases `conformance/authored_date_functions.py` (11, all AGREE), mutants
    `conformance/date_function_mutants.py` (5, all killed), corpus writer
    `conformance/date_function_evidence.py` (corpus 27). The core has 123 modules.
    `test-full`, `test-nix` and `test-scheduled` pass (model suite 381 s).

## Remaining

- Implementation, full checks, review, CI time, pull request A; then pull request B
  (claim corpus 27, `mustAgree`).
