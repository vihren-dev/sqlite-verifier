"""Authored coverage cases of the clock of ADR 0012 (slice 6e2).

Each statement of a script sees one clock value. `CURRENT_TIME`, `CURRENT_DATE` and
`CURRENT_TIMESTAMP` give it as text in every expression context of the model, an omitted
column with such a default gets it stored with the column's affinity, and ADD COLUMN with
such a default fails on a populated table. The recorder controls the clock (ADR 0005,
section 3.2): the setup runs at `SETUP_CLOCK`, and each statement of the SQL at its value
in `ClockCase.clocks`. The values lie on a year boundary and a millisecond before a second,
so that truncation and the clock of each statement are visible. Native SQLite is the only
source of outcomes.
"""

from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.execution_profile import ExecutionProfile, measured_profile
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_record import record_sql

TIMESTAMP = "R-07677-44926"
"""SQLite: the format for CURRENT_TIMESTAMP is "YYYY-MM-DD HH:MM:SS"."""
TIME = "R-62327-53843"
"""SQLite: for CURRENT_TIME, the format of the value is "HH:MM:SS"."""
DATE = "R-03775-43471"
"""SQLite: for CURRENT_DATE, "YYYY-MM-DD"."""
DEFAULT = "R-15363-55230"
"""SQLite: a time keyword default gives the new row a text of the current UTC date or time."""
ADD_COLUMN = "R-37287-38238"
"""SQLite: an added column may not have a time keyword default (on a populated table)."""

LAST_OF_2024 = 1735689599999
"""2024-12-31 23:59:59.999 in Unix milliseconds."""
FIRST_OF_2025 = 1735689600000
"""2025-01-01 00:00:00 in Unix milliseconds."""
SETUP_CLOCK = 1735603200000
"""2024-12-31 00:00:00 in Unix milliseconds, the clock of each setup statement."""

TABLE = "CREATE TABLE t(a, b INTEGER); INSERT INTO t VALUES('2024-12-31', 1), ('2025-01-01', 2);"
"""A table with a row before and a row on the date of `FIRST_OF_2025`."""
DEFAULTS = ("CREATE TABLE d(k, b TEXT DEFAULT CURRENT_TIMESTAMP, c INTEGER DEFAULT CURRENT_DATE, "
            "e REAL DEFAULT CURRENT_TIME, f NUMERIC DEFAULT CURRENT_DATE, g BLOB DEFAULT CURRENT_TIME);")
"""A table with a time keyword default in a column of each affinity."""


@dataclass(frozen=True)
class ClockCase:
    """One coverage case: setup and SQL, the clock value of each statement of the SQL in
    Unix milliseconds, the requirement identifiers it covers, and descriptive features."""

    name: str
    setup: str
    sql: str
    clocks: tuple[int, ...]
    requirements: tuple[str, ...]
    features: tuple[str, ...]


def definitions() -> list[ClockCase]:
    """The coverage cases of the clock."""
    case = ClockCase
    last, first = LAST_OF_2024, FIRST_OF_2025
    return [
        case("clock-keywords-fromless", "", "SELECT CURRENT_TIME, CURRENT_DATE, CURRENT_TIMESTAMP;", (last,),
             (TIME, DATE, TIMESTAMP), ("clock", "fromless", "truncation")),
        case("clock-where", TABLE, "SELECT a, b FROM t WHERE a = CURRENT_DATE;", (first,), (DATE,),
             ("clock", "where")),
        case("clock-set", TABLE, "UPDATE t SET a = CURRENT_TIME WHERE b = 1; SELECT a, b FROM t;", (last, last),
             (TIME,), ("clock", "update")),
        case("clock-values", TABLE, "INSERT INTO t VALUES(CURRENT_TIMESTAMP, CURRENT_DATE); SELECT a, b FROM t;",
             (last, last), (TIMESTAMP, DATE), ("clock", "values", "affinity")),
        case("clock-returning", TABLE, "INSERT INTO t VALUES(3, 3) RETURNING CURRENT_DATE, b;", (first,), (DATE,),
             ("clock", "returning")),
        case("clock-per-statement", TABLE,
             "INSERT INTO t VALUES(CURRENT_DATE, 3); INSERT INTO t VALUES(CURRENT_DATE, 4); SELECT a, b FROM t;",
             (last, first, first), (DATE,), ("clock", "statements")),
        case("clock-default-affinity", DEFAULTS,
             "INSERT INTO d(k) VALUES(1); INSERT INTO d(k) VALUES(2); SELECT k, b, c, e, f, g FROM d;",
             (last, first, first), (DEFAULT, TIMESTAMP, DATE, TIME), ("clock", "default", "affinity")),
        case("clock-default-empty-add-column", "CREATE TABLE t(a);",
             "ALTER TABLE t ADD COLUMN c DEFAULT CURRENT_TIMESTAMP; INSERT INTO t(a) VALUES(1); SELECT a, c FROM t;",
             (last, first, first), (ADD_COLUMN, DEFAULT), ("clock", "default", "add-column")),
        case("clock-default-populated-add-column", TABLE, "ALTER TABLE t ADD COLUMN c DEFAULT CURRENT_DATE;",
             (first,), (ADD_COLUMN,), ("clock", "default", "add-column", "native-error")),
    ]


def profile() -> ExecutionProfile:
    """A measured profile of format 3 with SQLite's default execution settings and the
    controlled clock."""
    with TemporaryDirectory(prefix="clock-profile-") as directory:
        connection = Connection(load_library(library_path()), Path(directory) / "measure.db")
        try:
            return measured_profile(connection, name="clock-default-v1", clock="unix-milliseconds-v1",
                                    format_version=3)
        finally:
            connection.close()


def records(cases: list[ClockCase] | None = None) -> list[dict[str, Json]]:
    """Record each case natively under the controlled clock as a version 5 record with
    outputs, in the part `clock`."""
    selected = definitions() if cases is None else cases
    measured = profile()
    return [{**record_sql(case.setup, case.sql, name=case.name, requirements=list(case.requirements), outputs=True,
                          profile=measured, setup_clock=SETUP_CLOCK, clock_values=list(case.clocks)),
             "part": "clock", "features": list(case.features)}
            for case in selected]
