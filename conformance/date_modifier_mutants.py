"""Mutants of the date and time modifiers (ADR 0012, amendment 5, slice 6g).

The task of slice 6g lists the changes that the conformance suite must notice. Each mutant
is one text change in a copy of the model, which `conformance.resolve_mutants.measure`
builds and runs against its target case of `conformance.authored_date_modifiers`.
"""

from conformance.resolve_mutants import SQLITE

ARITHMETIC = SQLITE + "Date/ModifierArithmetic.lean"
"""Amounts of time units."""
FUNCTIONS = SQLITE + "Date/Functions.lean"
"""The modifier loop of the functions."""
MODIFIER = SQLITE + "Date/Modifier.lean"
"""The keyword modifiers."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "month_clamped": (ARITHMETIC,
        "      ({ ({ p with month := p.month + whole }).normalizeMonth.computeFloor with "
        "validJulianMilliseconds := false },",
        "      ({ ({ p with month := p.month + whole, day := min p.day 28 }).normalizeMonth.computeFloor with\n"
        "        validJulianMilliseconds := false },"),
    "modifiers_right_to_left": (FUNCTIONS,
        "    | some parsed => match DateTime.applyModifiers 1 modifiers parsed with",
        "    | some parsed => match DateTime.applyModifiers 1 modifiers.reverse parsed with"),
    "start_of_month_as_year": (MODIFIER,
        "  if equalsKeyword unit TimeUnit.month.name then some { p with day := 1 }",
        "  if equalsKeyword unit TimeUnit.month.name then some { p with month := 1, day := 1 }"),
    "weekday_always_moves": (MODIFIER,
        "  let current := if current > weekday then current - 7 else current",
        "  let current := if current ≥ weekday then current - 7 else current"),
    "unixepoch_as_julian_day": (MODIFIER,
        "    else some (p.ofUnixSeconds julianMilliseconds)",
        "    else some p"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement.
The names follow the list in the task of slice 6g: a month added by clamping the day
instead of SQLite's normalization through the Julian day; modifiers applied from right to
left; `start of month` as `start of year`; `weekday` that moves a date already on that
weekday; `unixepoch` that keeps the number as a Julian day number."""

TARGETS: dict[str, tuple[str, ...]] = {
    "month_clamped": ("date-modifiers-amounts",), "modifiers_right_to_left": ("date-modifiers-order",),
    "start_of_month_as_year": ("date-modifiers-start-of",), "weekday_always_moves": ("date-modifiers-weekday",),
    "unixepoch_as_julian_day": ("date-modifiers-numbers",),
}
"""The authored case of `conformance.authored_date_modifiers` that each mutant changes."""

GUARDS: dict[str, str] = {
    "month_clamped": "rule:DateTime.addUnits", "modifiers_right_to_left": "rule:DateTime.ofArguments",
    "start_of_month_as_year": "rule:DateTime.applyStartOf", "weekday_always_moves": "rule:DateTime.applyWeekday",
    "unixepoch_as_julian_day": "rule:DateTime.applyUnixepochOrUtc",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
