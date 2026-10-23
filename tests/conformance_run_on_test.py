"""The recorder's mode that runs on after an SQL error (`conformance.native_record.record_sql`
with `run_on`, `conformance.native_statements.execute`).

A record of this mode has native record version 6 and one event for each statement, also after
a failed one. SQLite's prepare tail stops in the middle of some failed statements, so the
statement ends where `conformance.native_statement_end.complete_statement` says. Without the
mode, the recorder stops at the first error, as the old corpora need.
"""

from pathlib import Path

import pytest

from conformance import native_statements
from conformance.authored_resolution import profile
from conformance.corpus import native_replay
from conformance.native_record import record_sql

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]

SETUP = "CREATE TABLE t(a INTEGER);"
DUPLICATE = "CREATE TABLE u(a, a, b);"
"""A statement whose prepare tail SQLite ends after `a, a`, in the middle of the text."""
TRIGGER = " CREATE TRIGGER r AFTER INSERT ON missing BEGIN INSERT INTO t VALUES (2); END;"
"""A statement whose prepare tail SQLite ends before the trigger body."""
LATER = " INSERT INTO t VALUES (1); SELECT a FROM t;"


def test_run_on_records_each_statement_after_a_mid_text_prepare_error() -> None:
    """Each statement gives one event with the whole statement, the failed ones fail at prepare,
    the later ones run, and the native replay records the same events again."""
    record = record_sql(SETUP, DUPLICATE + TRIGGER + LATER, name="run-on", outputs=True, profile=profile(()),
                        run_on=True)
    trace = record["trace"]
    assert record["nativeVersion"] == 6
    assert [event["sql"] for event in trace] == [DUPLICATE, TRIGGER, " INSERT INTO t VALUES (1);", " SELECT a FROM t;"]
    assert [event["phase"] for event in trace] == ["prepare", "prepare", None, None]
    assert [event["primaryCode"] for event in trace] == [1, 1, 0, 0]
    assert len(trace[-1]["rows"]) == 1 and trace[-1]["columns"] == ["a"]
    native_replay([record])


def test_an_empty_statement_belongs_to_the_next_statement() -> None:
    """A lone `;` before a statement that fails in the middle of its text is part of that
    statement's event, as SQLite's prepare skips it, so the error is recorded once."""
    record = record_sql(SETUP, "; " + DUPLICATE + LATER, name="empty", outputs=True, profile=profile(()), run_on=True)
    assert [event["sql"] for event in record["trace"]] == ["; " + DUPLICATE, " INSERT INTO t VALUES (1);",
                                                           " SELECT a FROM t;"]
    assert [event["primaryCode"] for event in record["trace"]] == [1, 0, 0]


def test_a_character_that_sqlite_refuses_is_not_an_empty_statement() -> None:
    """A no-break space before `;` is not white space for SQLite, so the prefix up to that `;`
    is a statement of its own that fails, and the statement after it still runs."""
    record = record_sql(SETUP, "\u00a0;" + LATER, name="refused", outputs=True, profile=profile(()), run_on=True)
    assert [event["sql"] for event in record["trace"]] == ["\u00a0;", " INSERT INTO t VALUES (1);", " SELECT a FROM t;"]
    assert [event["primaryCode"] for event in record["trace"]] == [1, 0, 0]


def test_a_byte_order_mark_is_an_empty_statement() -> None:
    """SQLite's prepare skips a byte order mark before `;`, so that prefix belongs to the
    statement after it, and a failed statement after it gives one event."""
    record = record_sql(SETUP, "\ufeff; " + DUPLICATE + LATER, name="mark", outputs=True, profile=profile(()),
                        run_on=True)
    assert [event["sql"] for event in record["trace"]] == ["\ufeff; " + DUPLICATE, " INSERT INTO t VALUES (1);",
                                                           " SELECT a FROM t;"]
    assert [event["primaryCode"] for event in record["trace"]] == [1, 0, 0]


def test_a_boundary_that_differs_from_the_prepare_tail_is_refused(monkeypatch: pytest.MonkeyPatch) -> None:
    """When the complete statement and the prepare tail of a statement that prepares end at
    different places, the recording stops with that message, and not with an error of the
    connection's close, as the statement is finalized first."""
    monkeypatch.setattr(native_statements, "complete_statement", lambda connection, remaining: remaining[:5])
    with pytest.raises(ValueError, match="end at different places"):
        record_sql(SETUP, LATER, name="differs", outputs=True, profile=profile(()), run_on=True)


def test_default_mode_stops_at_the_first_error() -> None:
    """Without the mode, the trace ends at the failed statement, and the record has version 5."""
    record = record_sql(SETUP, DUPLICATE + LATER, name="stops", outputs=True, profile=profile(()))
    assert record["nativeVersion"] == 5 and len(record["trace"]) == 1
    assert record["trace"][0]["phase"] == "prepare"


def test_run_on_needs_a_measured_profile() -> None:
    """A recording that runs on without a measured profile is refused, with the case name."""
    with pytest.raises(ValueError, match="needs a measured profile: plain"):
        record_sql(SETUP, DUPLICATE + LATER, name="plain", outputs=True, run_on=True)
