# Date and time modifiers, slice 6g of ADR 0012: status

Created 2026-10-17. Status: DONE.
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
- 2026-10-17: implementation of pull request A.
  - Port of `parseModifier`, `autoAdjustDate`, `computeFloor` and `toLocaltime` in UTC
    under `Belay/Sqlite/Date/` (`LocalTime`, `ModifierArithmetic`, `NumericModifier`,
    `Modifier`, 88 checked examples): 280,000 differential modifier cases against native
    SQLite with `TZ=UTC0`, 0 mismatches, and the 200,000 cases of slice 6f still agree.
    Not modeled: `localtime_r`'s error, which UTC cannot reach.
  - The restriction `date-modifier` is gone; `dateCall` never fails.
  - Authored cases `conformance/authored_date_modifiers.py` (10, all AGREE), mutants
    `conformance/date_modifier_mutants.py` (5, all killed) in the date measurement, corpus
    writer `conformance/date_modifier_evidence.py` (corpus 28). The anchor of the slice 6f
    mutant `time_zone_ignored` follows the new result of `parseTimezone`. The core has 127
    modules. `test-full`, `test-nix` and `test-scheduled` pass.

- 2026-10-17: pull request A is #156 (CI time: `tests.model` 328 s to 334 s,
  `tests.harness` 22 s, `tests.frozen` 140 s to 141 s, scheduled mutants 383 s to 403 s).
  No upstream case changes its verdict.
- 2026-10-17: pull request B. Corpus 28 (10 cases, all AGREE) is frozen and claimed.

## Remaining

- None. This slice ends amendment 5 of ADR 0012.
