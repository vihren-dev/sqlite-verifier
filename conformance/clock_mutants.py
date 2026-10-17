"""Mutants of the clock (ADR 0012, amendment 5, slice 6e2).

The task of slice 6e2 lists the changes that the conformance suite must notice. Each
mutant is one text change in a copy of the model, which
`conformance.resolve_mutants.measure` builds and runs against its target case of
`conformance.authored_clock`.
"""

from conformance.resolve_mutants import SQLITE

EXECUTION = SQLITE + "SqlExecution.lean"
"""The script under a clock assignment."""
TEXT = SQLITE + "ClockText.lean"
"""The text of the time keywords."""
STATEMENT = SQLITE + "StatementClock.lean"
"""A statement at a clock value."""

MUTANTS: dict[str, tuple[str, str, str]] = {
    "clock_one_for_script": (EXECUTION,
        "  script.mapIdx fun position (statement : Resolved.Statement) => statement.atClock (clock position)",
        "  script.mapIdx fun _ (statement : Resolved.Statement) => statement.atClock (clock 0)"),
    "clock_date_with_time": (TEXT, "    | .date => .text (dateText (civilDateOfClock clock))",
        "    | .date => .text (timestampTextOfClock clock)"),
    "clock_seconds_rounded": (TEXT, "(dayMilliseconds.tmod 60000).tdiv 1000)",
        "((dayMilliseconds.tmod 60000) + 500).tdiv 1000)"),
    "clock_default_at_resolution": (STATEMENT,
        "  | .clocked statement cells => (statement.fillCells clock cells).expressionsAtClock clock",
        "  | .clocked statement cells => (statement.fillCells defaultDateClock cells).expressionsAtClock clock"),
}
"""Each mutant: the file under `packages/`, the exact text it changes, and the replacement. The
names follow the list in the task of slice 6e2: one clock value, the first statement's, for
all statements of a script; `CURRENT_DATE` with the time; seconds rounded instead of
truncated; the cells of an INSERT, such as an omitted value with a time default, at one
clock value fixed before the script runs (`defaultDateClock`), as if resolution evaluated
them, instead of the clock value of their statement."""

TARGETS: dict[str, tuple[str, ...]] = {
    "clock_one_for_script": ("clock-per-statement",), "clock_date_with_time": ("clock-keywords-fromless",),
    "clock_seconds_rounded": ("clock-keywords-fromless",), "clock_default_at_resolution": ("clock-default-affinity",),
}
"""The authored case of `conformance.authored_clock` that each mutant changes."""

GUARDS: dict[str, str] = {
    "clock_one_for_script": "rule:scriptAtClock", "clock_date_with_time": "rule:TimeKeyword.value",
    "clock_seconds_rounded": "rule:timeOfDayOfClock", "clock_default_at_resolution": "rule:Statement.atClock",
}
"""What each mutant guards: `rule:` and the Lean declaration of its file that the mutant
changes. `conformance.mutant_guards` checks every entry."""
