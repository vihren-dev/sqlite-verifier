# Date and time functions, slice 6f of ADR 0012

Created 2026-10-17. Status: open.
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), "Amendment 5", "Date and
time functions (slice 6f)", owner decisions 2, 3 and 8. Related: slice 6e2
([task](20261017-clock.task.md)), whose clock gives `now`; slice 6g (modifiers) builds on
these functions.

## Pull requests

- **Pull request A (subject):** the six functions in the model, examples, proofs, authored
  coverage cases, mutants and a corpus writer. No change under `judge/` or `integrity/`;
  `Contract.lean` does not change.
- **Pull request B (judge, owner approval):** the coverage corpus (version 27) is frozen
  and claimed, and upstream cases that newly agree are added to `mustAgree`.

## Outcome

1. **Functions.** `date`, `time`, `datetime`, `julianday`, `unixepoch` and `strftime`
   give SQLite 3.51.0's value in every expression context of the model (queries, `WHERE`,
   `SET`, `VALUES`, `RETURNING`, a `json_each` argument), with one time value argument, or
   none, which is `now`. `strftime` takes its format first and supports every format
   specifier of SQLite 3.51.0 (owner decision 3).
2. **Time values.** Every time value that SQLite reads without a modifier: each text
   format of `lang_datefunc.html` (dates, times, a `T` separator, fractional seconds, a
   time zone suffix), `now`, and a number, which is a Julian day number. A value that
   SQLite cannot read gives NULL, as do NULL arguments. The result types are SQLite's:
   text for `date`, `time`, `datetime` and `strftime`, REAL for `julianday`, INTEGER for
   `unixepoch`.
3. **Clock.** `now`, written or read from a column, gives the statement's clock value
   (slice 6e2), so a call reads the clock unless the model can see that its arguments
   are not `now`. Within one statement every call sees one clock value, as in SQLite.
4. **Restrictions.** A modifier argument (a second argument, or a third for `strftime`)
   is a model restriction until slice 6g, with its own registry entry. Other functions
   stay `unmodeled-function`.
5. **Evidence.** Authored coverage cases agree with native SQLite 3.51.0 (under the
   controlled clock where they read `now`) and have kernel proofs; each mutant below
   changes a verdict; the verdict counts of the claimed corpora do not go down.

## Tests

- Lean examples: each function over each text format, numbers at the edges of SQLite's
  range, unreadable text, NULL, and each `strftime` specifier, each checked against
  native SQLite.
- Authored coverage cases (native SQLite as the oracle): each function in a query
  without FROM, over a column, in `WHERE`, `SET`, `VALUES` and `RETURNING`; `now` written
  and read from a column under the controlled clock; two calls in one statement; every
  `strftime` specifier; unreadable values; the restriction for a modifier.
- Mutants, each changing the verdict of an authored case: `now` read once per script;
  `julianday` as an integer; `%W` as `%U`; a time zone suffix ignored; a number read as
  Unix seconds instead of a Julian day number.

## Key points for the implementer

- **SQLite's source is the specification.** `date.c` of 3.51.0: `isDate`,
  `parseDateOrTime`, `parseYyyyMmDd`, `parseHhMmSs`, `parseTimezone`, `computeJD`,
  `computeYMD_HMS`, `setRawDateNumber` and `strftimeFunc`. The arithmetic mixes 64-bit
  integers and doubles (fractional seconds, `julianday`'s value), so a port must follow
  it step by step; differential tests against the pinned native build are the check, as
  for `ClockText.lean`. A REAL result is rendered by the model's existing REAL text.
- **Reading the clock.** `Expr.readsClock` and `Expr.atClock` (`ClockSubstitution.lean`)
  decide which statements depend on the clock. A date function call over a column may
  read `now` from a row, so the call must carry the statement's clock value after
  `atClock`, not only literal `now`.
- **Resolution.** Function names resolve in `Resolution/Calls.lean`
  (`jsonFunctionNamed`); argument counts are SQLite's prepare checks
  (`wrong number of arguments`), where SQLite has them. The restriction registry is
  `Resolution/Restrictions.lean` with `RestrictionText.lean`,
  `conformance/restriction_examples.py` and `docs/semantic-subset.md`.
- **Constant values.** A `VALUES` item or a constant `SET` value that calls these
  functions reads the clock, so it becomes a clock cell (`Resolution/ClockRows.lean`).
- **Cost.** Kernel proofs of conformance cases evaluate the port; keep the cases small
  and measure `tests.model`.
