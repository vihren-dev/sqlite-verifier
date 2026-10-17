"""Authored coverage cases of the date and time modifiers of ADR 0012 (slice 6g).

The six functions of slice 6f with modifiers after the time value: amounts of each unit,
with SQLite's month and year normalization, time and date offsets, `start of`, `weekday`,
`unixepoch`, `julianday` and `auto` after numbers, `localtime` and `utc` in UTC, `subsec`,
`ceiling` and `floor`, several modifiers in order, modifiers from a column and with `now`,
and modifiers that SQLite refuses. The recorder controls the clock
(`conformance.authored_clock`). Native SQLite is the only source of outcomes.
"""

from conformance.authored_clock import FIRST_OF_2025, LAST_OF_2024, ClockCase, records as clock_records
from conformance.case_format import Json

MODIFIERS = "R-05483-40384"
"""SQLite: the time value can be followed by zero or more modifiers."""
ORDER = "R-45424-59143"
"""SQLite: modifiers are applied from left to right; order is important."""
AMOUNTS = "R-26110-08661"
"""SQLite: the first thirteen modifiers add the specified amount of time."""
START_OF = "R-39059-18244"
"""SQLite: the "start of" modifiers shift the date back to the start of the month, year or
day."""
WEEKDAY = "R-59400-47238"
"""SQLite: "weekday N" advances the date to the next date with weekday number N."""
WEEKDAY_SAME = "R-59177-30964"
"""SQLite: "weekday N" leaves a date on that weekday unchanged."""
UNIXEPOCH = "R-23075-39245"
"""SQLite: "unixepoch" reads the number as Unix time."""
JULIANDAY = "R-32483-36353"
"""SQLite: "julianday" reads the number as a Julian day number."""
AUTO = "R-24981-18755"
"""SQLite: a number followed by "auto" may be read as a Unix timestamp."""
LOCALTIME = "R-16368-29905"
"""SQLite: "localtime" moves a UTC time value to local time."""
UTC = "R-08015-61720"
"""SQLite: "utc" is the opposite of "localtime"."""

TABLE = ("CREATE TABLE m(k INTEGER, v, modifier); INSERT INTO m VALUES (1, '2024-01-31', '+1 month'), "
         "(2, '2024-05-17 13:14:15', 'start of year'), (3, 1700000000, 'unixepoch'), (4, 'now', 'start of day'), "
         "(5, '2024-05-17', 'weekday 0'), (6, '2024-01-01', 'bogus'), (7, '2024-01-01', NULL);")
"""A table of time values with a modifier in each row, `now` and two that SQLite refuses."""


def definitions() -> list[ClockCase]:
    """The coverage cases of the date and time modifiers."""
    case = ClockCase
    last, first = LAST_OF_2024, FIRST_OF_2025
    return [
        case("date-modifiers-amounts", "",
             "SELECT datetime('2024-01-31 12:00', '+1 day'), datetime('2024-01-31 12:00', '-36 hours'), "
             "datetime('2024-01-31 12:00', '+90 minutes'), datetime('2024-01-31 12:00', '+3.5 seconds', 'subsec'), "
             "date('2024-01-31', '+1 month'), date('2024-02-29', '+1 year'), date('2024-02-29', '-1 years'), "
             "datetime('2024-01-01', '+1.5 days');", (last,), (MODIFIERS, AMOUNTS), ("date-modifiers", "amounts")),
        case("date-modifiers-offsets", "",
             "SELECT datetime('2024-01-01 10:00', '+02:30'), datetime('2024-01-01 10:00', '-01:15:30.5'), "
             "datetime('2024-01-31', '+0001-01-01 01:00'), datetime('2024-03-31', '-0000-01-00');", (last,),
             (AMOUNTS,), ("date-modifiers", "offsets")),
        case("date-modifiers-start-of", "",
             "SELECT datetime('2024-05-17 13:14:15', 'start of month'), "
             "datetime('2024-05-17 13:14:15', 'start of year'), datetime('2024-05-17 13:14:15', 'start of day');",
             (last,), (START_OF,), ("date-modifiers", "start-of")),
        case("date-modifiers-weekday", "",
             "SELECT date('2024-05-17', 'weekday 5'), date('2024-05-17', 'weekday 0'), "
             "date('2024-05-17', 'weekday 1');", (last,), (WEEKDAY, WEEKDAY_SAME), ("date-modifiers", "weekday")),
        case("date-modifiers-numbers", "",
             "SELECT datetime(1700000000, 'unixepoch'), datetime(2460369.5, 'julianday'), "
             "datetime(1700000000, 'auto'), datetime(2460369.5, 'auto'), datetime('2024-01-01', 'julianday'), "
             "unixepoch(1700000000.125, 'unixepoch', 'subsec');", (last,), (UNIXEPOCH, JULIANDAY, AUTO),
             ("date-modifiers", "numbers")),
        case("date-modifiers-local-time", "",
             "SELECT datetime('2024-01-01 10:00', 'localtime'), datetime('2024-01-01 10:00', 'utc'), "
             "datetime('1900-06-01', 'localtime'), datetime('2024-01-01 10:00', 'localtime', 'utc');", (last,),
             (LOCALTIME, UTC), ("date-modifiers", "local-time")),
        case("date-modifiers-order", "",
             "SELECT date('2024-01-31', 'start of month', '+1 month'), "
             "date('2024-01-31', '+1 month', 'start of month'), date('2024-01-31', '+1 month', 'floor'), "
             "date('2024-01-31', '+1 month', 'ceiling');", (last,),
             (ORDER, START_OF), ("date-modifiers", "order")),
        case("date-modifiers-columns", TABLE, "SELECT k, datetime(v, modifier) FROM m ORDER BY k;", (last,),
             (MODIFIERS,), ("date-modifiers", "columns", "now")),
        case("date-modifiers-refused", "",
             "SELECT date('2024-01-01', 'bogus'), date('2024-01-01', NULL), date('2024-01-01', '+1 fortnight'), "
             "date('2024-01-01', 'weekday 7'), date('2024-01-01', 'unixepoch'), date(1e20, '+1 day');", (last,),
             (MODIFIERS,), ("date-modifiers", "refused")),
        case("date-modifiers-writes", TABLE,
             "INSERT INTO m VALUES (8, date('now', '+7 days'), NULL); UPDATE m SET v = strftime('%s', 'now', "
             "'start of day') WHERE k = 1; SELECT k, v FROM m WHERE k = 1 OR k = 8 ORDER BY k;", (last, first, first),
             (MODIFIERS,), ("date-modifiers", "values", "update", "now")),
    ]


def records(cases: list[ClockCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively under the controlled clock as a version 5 record with
    outputs, in the part `date-modifiers`."""
    return clock_records(definitions() if cases is None else cases, part="date-modifiers")
