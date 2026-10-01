"""Closed auxiliary contexts recover only through faithful read-only prefix replay."""

import pytest

from conformance.upstream_pilot import assertions
from conformance.upstream_fidelity import check_results
from conformance.native_record import record_sql
from conformance.case_format import Json

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def candidate(events: list[tuple[str, ...]]) -> dict[str, Json]:
    """Decode the real capture transport and return the last assertion."""
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    return assertions(encoded)[-1]


def test_closed_auxiliary_read_prefix_recovers() -> None:
    """Live handles exclude; equivalent read results after closure permit recording."""
    events = [("reset", "/tmp/main.db"),
        ("sql", "db", "CREATE TABLE t(v); INSERT INTO t VALUES(5);", "0", "eval"), ("result", "db", "0"),
        ("open", "db2", "/tmp/main.db"), ("begin", "live", "5"),
        ("sql", "db", "SELECT v FROM t;", "0", "eval"), ("result", "db", "0", "5"), ("end", "live")]
    assert "multiple connections" in candidate(events)["exclusions"]
    events += [("sql", "db2", "SELECT v FROM t;", "0", "eval"), ("result", "db2", "0", "5"),
        ("close", "db2"), ("begin", "closed", "5"), ("sql", "db", "SELECT v FROM t;", "0", "eval"),
        ("result", "db", "0", "5"), ("end", "closed")]
    case = candidate(events)
    assert not case["exclusions"]
    assert "aux:eval" in case["prefixHelpers"]
    native = record_sql(case["prefix"], case["commands"][0], name="closed", setup_helpers=case["prefixHelpers"])
    check_results(native, case)


def test_closed_reader_does_not_hide_uncommitted_difference() -> None:
    """A committed auxiliary read differs from replay on an uncommitted primary."""
    events = [("reset", "/tmp/main.db"),
        ("sql", "db", "CREATE TABLE t(v); INSERT INTO t VALUES(1); BEGIN; INSERT INTO t VALUES(2);", "0", "eval"),
        ("result", "db", "0"), ("open", "db2", "/tmp/main.db"),
        ("sql", "db2", "SELECT v FROM t ORDER BY v;", "0", "eval"), ("result", "db2", "0", "1"),
        ("sql", "db", "ROLLBACK;", "0", "eval"), ("result", "db", "0"), ("close", "db2"),
        ("begin", "closed", "1"), ("sql", "db", "SELECT v FROM t;", "0", "eval"),
        ("result", "db", "0", "1"), ("end", "closed")]
    case = candidate(events)
    assert not case["exclusions"]
    with pytest.raises(ValueError, match="primary transaction"):
        record_sql(case["prefix"], case["commands"][0], name="false-recovery", setup_helpers=case["prefixHelpers"])
    case["prefix"][1] = "INSERT INTO t VALUES(2);"
    case["prefix"][0] = "CREATE TABLE t(v); INSERT INTO t VALUES(1);"
    with pytest.raises(ValueError, match="read-only SELECT"):
        record_sql(case["prefix"], case["commands"][0], name="aux-write", setup_helpers=case["prefixHelpers"])


def test_reset_does_not_close_an_auxiliary_handle() -> None:
    """Only the auxiliary close event clears its lifetime exclusion."""
    events = [("open", "db2", "/tmp/other.db"), ("reset", "/tmp/main.db"),
        ("begin", "reset", "1"), ("sql", "db", "SELECT 1;", "0", "eval"),
        ("result", "db", "0", "1"), ("end", "reset")]
    assert "multiple connections" in candidate(events)["exclusions"]
    events.insert(0, ("exclude", "connection command renamed"))
    assert "connection command renamed" in candidate(events)["exclusions"]


def test_auxiliary_file_identity_is_required() -> None:
    """Coincidentally equal scalar results cannot prove a different database identical."""
    events = [("reset", "/tmp/main.db"), ("open", "db2", "/tmp/other.db"),
        ("sql", "db2", "SELECT 1;", "0", "eval"), ("result", "db2", "0", "1"), ("close", "db2"),
        ("begin", "other", "1"), ("sql", "db", "SELECT 1;", "0", "eval"),
        ("result", "db", "0", "1"), ("end", "other")]
    assert "auxiliary database differs from primary" in candidate(events)["exclusions"]
