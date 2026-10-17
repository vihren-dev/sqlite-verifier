"""Mutants of the date and time functions (ADR 0012, amendment 5, slice 6f).

The task of slice 6f lists the changes that the conformance suite must notice. Each mutant
is one text change in a copy of the model, which `conformance.resolve_mutants.measure`
builds and runs against its target case of `conformance.authored_date_functions`.
"""

from conformance.resolve_mutants import SQLITE

SUBSTITUTION = SQLITE + "ClockSubstitution.lean"
"""An expression at the statement's clock value."""
FUNCTIONS = SQLITE + "Date/Functions.lean"
"""The values of the six functions."""
STRFTIME = SQLITE + "Date/Strftime.lean"
"""The specifiers of `strftime`."""
PARSE = SQLITE + "Date/Parse.lean"
"""The text time values."""
DATE_TIME = SQLITE + "Date/DateTime.lean"
"""Numeric time values."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "now_without_statement_clock": (SUBSTITUTION,
        "    .date function (arguments.atClock clock) (if function.readsNow arguments then clock else stored)",
        "    .date function (arguments.atClock clock) stored"),
    "julianday_as_integer": (FUNCTIONS,
        "      | .julianday => realValue (Float.ofInt x.computeJulianDay.julianMilliseconds / 86400000.0)",
        "      | .julianday => .integer (x.computeJulianDay.julianMilliseconds / 86400000)"),
    "week_from_monday_as_sunday": (STRFTIME,
        "  | .weekFromMonday => formatInteger 2 true ((x.daysAfterJanuaryFirst - x.daysAfterMonday + 7).tdiv 7)",
        "  | .weekFromMonday => formatInteger 2 true ((x.daysAfterJanuaryFirst - x.daysAfterSunday + 7).tdiv 7)"),
    "time_zone_ignored": (PARSE,
        "          if onlySpaces rest then some (if marker == 45 then -offset else offset) else none",
        "          if onlySpaces rest then some 0 else none"),
    "number_as_unix_seconds": (DATE_TIME,
        "    { raw with julianMilliseconds := doubleToInt64 (number * 86400000.0 + 0.5),",
        "    { raw with julianMilliseconds := doubleToInt64 (number * 1000.0 + 0.5) + 210866760000000,"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
The names follow the list in the task of slice 6f: `now` without the statement's clock
value (the task's `now` read once per script is `clock_one_for_script` of
`conformance.clock_mutants`, which the clock cases already kill); `julianday` as an
integer; `%W` counted from Sunday as `%U` is; a time zone suffix ignored; a number read as
Unix seconds instead of a Julian day number."""

TARGETS: dict[str, tuple[str, ...]] = {
    "now_without_statement_clock": ("date-functions-now",), "julianday_as_integer": ("date-functions-fromless",),
    "week_from_monday_as_sunday": ("date-functions-specifiers",), "time_zone_ignored": ("date-functions-time-zones",),
    "number_as_unix_seconds": ("date-functions-numbers",),
}
"""The authored case of `conformance.authored_date_functions` that each mutant changes."""

GUARDS: dict[str, str] = {
    "now_without_statement_clock": "rule:Expr.atClock", "julianday_as_integer": "rule:Resolved.DateFunction.value",
    "week_from_monday_as_sunday": "rule:StrftimeSpecifier.text", "time_zone_ignored": "rule:parseTimezone",
    "number_as_unix_seconds": "rule:DateTime.ofRawNumber",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
