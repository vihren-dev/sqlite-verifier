# Date and time modifiers, slice 6g of ADR 0012

Created 2026-10-17. Status: DONE (pull requests #156 and its claim).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), "Amendment 5", "Date and
time modifiers (slice 6g)", owner decisions 3 and 6. Related: slice 6f
([task](20261017-date-functions.task.md)), whose functions these modifiers extend.

## Pull requests

- **Pull request A (subject):** the modifiers in the model, examples, authored coverage
  cases, mutants and a corpus writer. No change under `judge/` or `integrity/`;
  `Contract.lean` does not change.
- **Pull request B (judge, owner approval):** the coverage corpus (version 28) is frozen
  and claimed, and upstream cases that newly agree are added to `mustAgree`.

## Outcome

1. **Modifiers.** The six functions of slice 6f accept any number of modifiers after the
   time value, applied from left to right as SQLite 3.51.0 applies them: every modifier
   of `lang_datefunc.html` and of `parseModifier` (`NNN days`, `hours`, `minutes`,
   `seconds`, `months`, `years`, `±HH:MM[:SS[.SSS]]`, `±YYYY-MM-DD[ HH:MM[:SS[.SSS]]]`,
   `start of month`, `year`, `day`, `weekday N`, `unixepoch`, `julianday`, `auto`,
   `localtime`, `utc`, `subsec`, `subsecond`, `ceiling`, `floor`), with SQLite's
   normalization: `date('2024-01-31', '+1 month')` is `2024-03-02`. A modifier that
   SQLite refuses gives NULL. The restriction `date-modifier` leaves the registry.
2. **Time zone.** `localtime` and `utc` use the time zone of the execution profile (owner
   decision 6). The model implements UTC, the zone in which the recorder runs SQLite and
   the only zone that `ExecutionProfile` accepts today; a profile with another zone needs
   a model change first.
3. **Evidence.** Authored coverage cases agree with native SQLite 3.51.0 and have kernel
   proofs; each mutant below changes a verdict; the verdict counts of the claimed corpora
   do not go down.

## Tests

- Lean examples: each modifier, its boundaries and its refusals, checked against native
  SQLite; a differential run against native SQLite.
- Authored coverage cases: each modifier kind in a query, over a column and with `now`
  under the controlled clock; several modifiers in order; month and year arithmetic at
  month ends and leap days; `weekday` on the same and other days; `unixepoch`,
  `julianday` and `auto` after numbers; `localtime` and `utc` in UTC; refused modifiers.
- Mutants, each changing the verdict of an authored case: a month added without
  normalization; modifiers applied from right to left; `start of month` as `start of
  year`; `weekday` that always moves; `unixepoch` read as a Julian day number.

## Key points for the implementer

- **SQLite's source is the specification.** `date.c` of 3.51.0: `parseModifier`,
  `autoAdjustDate`, `computeFloor`, `toLocaltime` and the modifier branch of `isDate`. The
  port of slice 6f (`Belay/Sqlite/Date/`) holds the `DateTime` structure without the
  fields that only modifiers read (`isUtc`, `isLocal`, `nFloor`); they come back here.
- **Local time.** `toLocaltime` calls the C library's `localtime_r`, and it moves a date
  outside the years 1970 to 2037 into that range before the call. In UTC the conversion
  has no offset, but the range handling and the errors stay; follow the source and check
  natively.
- **Profile.** The profile records its time zone and refuses every zone other than UTC
  (`conformance/execution_profile.py`); the model's scope is `conformance/profile_scope.py`.
- **Resolution.** `dateCall` in `Resolution/Calls.lean` refuses modifiers today; the
  clock rule (`DateFunction.readsNow`) does not change, because no modifier reads the
  clock.
