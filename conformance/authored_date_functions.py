"""Authored coverage cases of the date and time functions of ADR 0012 (slice 6f).

`date`, `time`, `datetime`, `julianday`, `unixepoch` and `strftime` with one time value or
none: each text format, numbers, time zone suffixes, unreadable values and NULL, every
`strftime` specifier, and `now`, written and read from a column. The recorder controls the
clock (`conformance.authored_clock`), so that `now` is the clock value of its statement.
Native SQLite is the only source of outcomes.
"""

from conformance.authored_clock import FIRST_OF_2025, LAST_OF_2024, ClockCase, records as clock_records
from conformance.case_format import Json

DATE = "R-46397-09573"
"""SQLite: the date() function returns the date as text in this format: YYYY-MM-DD."""
TIME = "R-14068-31774"
"""SQLite: the time() function returns the time as text as HH:MM:SS."""
JULIANDAY = "R-43640-59273"
"""SQLite: the julianday() function returns the fractional number of days since noon in
Greenwich on November 24, 4714 B.C."""
UNIXEPOCH = "R-30877-63179"
"""SQLite: the unixepoch() function returns the number of seconds since 1970-01-01 00:00:00
UTC."""
STRFTIME = "R-63811-08743"
"""SQLite: strftime() returns the date formatted according to its first argument."""
NOW = "R-48198-01058"
"""SQLite: the string 'now' is the current date and time of the VFS clock."""
OMITTED = "R-27529-59767"
"""SQLite: an omitted time value is 'now'."""
SAME_NOW = "R-34818-13664"
"""SQLite: 'now' gives the same value for every call within one sqlite3_step()."""
NUMBER = "R-11474-58635"
"""SQLite: format 12 is the Julian day number as an integer or floating point value."""
RANGE = "R-52653-05256"
"""SQLite: the functions work for dates between 0000-01-01 and 9999-12-31."""
TIME_ONLY = "R-02526-60953"
"""SQLite: formats that specify only a time assume a date of 2000-01-01."""

VALUES = ("CREATE TABLE d(k INTEGER, v); INSERT INTO d VALUES (1, '2024-02-29 13:45:30.250'), "
          "(2, '2023-12-31T23:59:59Z'), (3, '12:30'), (4, 2460369.5), (5, 'now'), (6, 'not a date'), "
          "(7, NULL), (8, '2024-01-01 10:00:00+05:30');")
"""A table of time values: a date with fractional seconds, a `T` separator with `Z`, a time
only, a Julian day number, `now`, unreadable text, NULL and a time zone offset."""
SPECIFIERS = "%d %e %f %F %H %I %j %J %k %l %m %M %p %P %R %s %S %T %u %w %W %U %V %G %g %Y %%"
"""Every `strftime` specifier of SQLite 3.51.0, with the escaped `%`."""


def definitions() -> list[ClockCase]:
    """The coverage cases of the date and time functions."""
    case = ClockCase
    last, first = LAST_OF_2024, FIRST_OF_2025
    return [
        case("date-functions-fromless", "",
             "SELECT date('2024-02-29'), time('13:45:30.250'), datetime('2024-02-29T13:45'), "
             "julianday('2024-02-29 12:00'), unixepoch('2024-02-29 13:45:30'), "
             "strftime('%Y-%m-%d %H:%M:%f', '2024-02-29 13:45:30.25');", (last,),
             (DATE, TIME, JULIANDAY, UNIXEPOCH, STRFTIME), ("date-functions", "fromless")),
        case("date-functions-columns", VALUES,
             "SELECT k, date(v), time(v), datetime(v), julianday(v), unixepoch(v) FROM d ORDER BY k;", (last,),
             (DATE, TIME, JULIANDAY, UNIXEPOCH, NOW, TIME_ONLY), ("date-functions", "columns", "now")),
        case("date-functions-now", "",
             "SELECT date(), time(), datetime('now'), julianday('NOW'), unixepoch(), strftime('%s'), "
             "strftime('%f', 'subsec');", (last,), (NOW, OMITTED, SAME_NOW), ("date-functions", "now")),
        case("date-functions-per-statement", VALUES,
             "INSERT INTO d VALUES (9, datetime('now')); INSERT INTO d VALUES (10, datetime()); "
             "SELECT k, v FROM d WHERE k > 8 ORDER BY k;", (last, first, first),
             (NOW, SAME_NOW), ("date-functions", "now", "statements", "values")),
        case("date-functions-where", VALUES, "SELECT k FROM d WHERE date(v) = '2024-02-29' ORDER BY k;", (last,),
             (DATE,), ("date-functions", "where")),
        case("date-functions-set", VALUES,
             "UPDATE d SET v = strftime('%j', v) WHERE k < 5; SELECT k, v FROM d ORDER BY k;", (last, last),
             (STRFTIME,), ("date-functions", "update")),
        case("date-functions-returning", VALUES,
             "INSERT INTO d VALUES (11, '2024-07-04') RETURNING julianday(v), unixepoch(v), date(k);", (first,),
             (JULIANDAY, UNIXEPOCH), ("date-functions", "returning")),
        case("date-functions-specifiers", "",
             f"SELECT strftime('{SPECIFIERS}', '2024-12-30 15:04:05.678'), "
             f"strftime('{SPECIFIERS}', '2021-01-03 00:00:00'), strftime('%Q', '2024-01-01');", (last,),
             (STRFTIME,), ("date-functions", "strftime")),
        case("date-functions-unreadable", "",
             "SELECT date('2023-02-31'), date('2023-13-01'), date('x'), date(NULL), julianday(-1), "
             "julianday(5373484.5), date(X'323032342d30312d3031'), time('24:00');", (last,),
             (DATE, RANGE), ("date-functions", "unreadable", "normalization")),
        case("date-functions-numbers", "",
             "SELECT date(0), datetime(2460369.75), julianday(2460369), unixepoch(2440587.5), "
             "date('2460369.5');", (last,), (NUMBER, JULIANDAY), ("date-functions", "numbers")),
        case("date-functions-time-zones", "",
             "SELECT datetime('2024-01-01 10:00:00+05:30'), datetime('2024-01-01T10:00Z'), "
             "time('10:00-02:00');", (last,), (DATE, TIME), ("date-functions", "time-zone")),
    ]


def records(cases: list[ClockCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively under the controlled clock as a version 5 record with
    outputs, in the part `date-functions`."""
    return clock_records(definitions() if cases is None else cases, part="date-functions")
