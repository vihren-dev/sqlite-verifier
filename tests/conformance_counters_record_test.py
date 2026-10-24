"""The recorder's mode that records the connection counters (`conformance.native_record.record_sql`
with `counters`, `conformance.native_counters.read_counters`; ADR 0024, D1).

A record of this mode has native record version 7: version 6 and the three counters of the writer
connection just before the migration. The native replay records the case again and compares the
counters with the stored ones.
"""

import pytest

from conformance.authored_resolution import profile
from conformance.case_format import Json
from conformance.corpus import native_replay
from conformance.native_record import record_sql

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]

TABLE = "CREATE TABLE t(a INTEGER PRIMARY KEY, b);"
WRITES = "INSERT INTO t VALUES (7, 1), (9, 2); UPDATE t SET b = 3 WHERE a = 7;"
LATER = " SELECT changes();"


def counted(setup: str | list[str | dict[str, Json]], **options: bool) -> dict[str, Json]:
    """Record `LATER` after the setup in the mode that records counters."""
    return record_sql(setup, LATER, name="counted", outputs=True, profile=profile(()), run_on=True, **options)


def test_the_counters_are_those_of_the_setup_writes() -> None:
    """A setup that writes leaves the changes of its last statement, the total of all its changes
    and the rowid of its last insert; the record has version 7."""
    record = counted(TABLE + WRITES, counters=True)
    assert record["nativeVersion"] == 7
    assert record["counters"] == {"changes": 1, "totalChanges": 3, "lastInsertRowid": 9}
    native_replay([record])


def test_a_reopened_connection_starts_with_zero_counters() -> None:
    """After a reopen of the writer connection, a new connection has 0 for each counter."""
    record = counted([TABLE + WRITES, {"reopen": True}], counters=True)
    assert record["counters"] == {"changes": 0, "totalChanges": 0, "lastInsertRowid": 0}


def test_a_record_without_the_mode_has_no_counters() -> None:
    """Without `counters`, the record keeps its version 6 and has no counters field."""
    record = counted(TABLE + WRITES)
    assert record["nativeVersion"] == 6 and "counters" not in record


def test_counters_need_the_run_on_mode() -> None:
    """A recording with counters but without `run_on` is refused, and the error says why."""
    with pytest.raises(ValueError, match="needs run_on"):
        record_sql(TABLE, LATER, name="stopped", outputs=True, profile=profile(()), counters=True)


def test_the_native_replay_checks_the_counters() -> None:
    """A stored version 7 record with another start counter fails the native replay, because the
    counters are part of the evidence."""
    record = counted(TABLE + WRITES, counters=True)
    record["counters"] = {**record["counters"], "lastInsertRowid": 8}
    with pytest.raises(ValueError, match="Native replay changed"):
        native_replay([record])
