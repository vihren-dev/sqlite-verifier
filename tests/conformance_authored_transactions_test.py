"""Actual immediate groups retain outputs, transaction isolation and first-error state."""

import pytest

from conformance.authored_cases import definitions as historical_definitions, records
from conformance.authored_boundaries import definitions as historical_boundaries
from conformance.authored_review import definitions as historical_review
from conformance.authored_transactions import definitions
from conformance.case_format import Json
from conformance.native_connection import Row
from conformance.native_replay import decode_rows, output_wire

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture(scope="module")
def transactions() -> dict[str, dict[str, Json]]:
    """Acquire only new definitions; each native statement has the shared five-second deadline."""
    return {record["name"]: record for record in records(definitions())}


def table_values(snapshot: dict[str, Json], name: str) -> list[Row]:
    """Read table rows independently of schema ordering and statement output ordering."""
    table = next(table for table in snapshot["tables"] if table["name"] == name)
    return decode_rows([row["values"] for row in table["rows"]])


def test_groups_retain_typed_outputs_and_historical_definitions(transactions: dict[str, dict[str, Json]]) -> None:
    """Five real BEGIN IMMEDIATE groups supplement the unchanged historical catalogs."""
    assert len(transactions) == 5
    assert len(historical_definitions()) == 43 and len(historical_boundaries()) == 23
    assert len(historical_review()) == 3
    for record in transactions.values():
        assert record["nativeVersion"] == 4 and record["requirements"] == []
        assert record["profile"]["transactionMode"] == "immediate"
        assert record["trace"][0]["sql"].strip() == "BEGIN IMMEDIATE;"
        assert not record["initial"]["transactionOpen"]
        for event in record["trace"]:
            output_wire(event)
            assert event["columnCount"] == len(event["columns"])


def test_commit_publishes_schema_defaults_indexes_and_writes(transactions: dict[str, dict[str, Json]]) -> None:
    """The observer retains the initial schema until COMMIT publishes all writer changes."""
    record = transactions["immediate-schema-write-commit"]
    trace = record["trace"]
    assert len(trace) == 8 and all(event["primaryCode"] == event["extendedCode"] == 0 for event in trace)
    assert [event["changes"] for event in trace] == [None, None, None, 1, 1, None, None, None]
    assert all(event["transactionOpen"] for event in trace[:6])
    assert all(event["persisted"] == record["initial"]["visible"] for event in trace[:6])
    assert decode_rows([trace[3]["parameters"]]) == [((3, b"kept"), (1, 7))]
    assert trace[3]["columns"] == ["id", "v", "note"]
    assert decode_rows(trace[3]["rows"]) == [((3, b"kept"), (1, 7), (3, b"new"))]
    assert decode_rows([trace[4]["parameters"]]) == [((3, b"seed"),)]
    assert decode_rows(trace[4]["rows"]) == [((3, b"seed"), (1, 3))]
    expected = [((3, b"kept"), (1, 7), (3, b"new")), ((3, b"seed"), (1, 3), (3, b"new"))]
    assert decode_rows(trace[5]["rows"]) == decode_rows(trace[7]["rows"]) == expected
    assert not trace[6]["transactionOpen"] and not trace[7]["transactionOpen"]
    assert trace[6]["visible"] == trace[6]["persisted"] == trace[5]["visible"]
    assert any(decode_rows([row])[0][1] == (3, b"ledger_by_v") for row in trace[6]["persisted"]["schema"])


def test_explicit_rollback_removes_schema_and_write_group(transactions: dict[str, dict[str, Json]]) -> None:
    """ROLLBACK removes the new table and restores rows that were changed earlier in the group."""
    record = transactions["immediate-schema-write-rollback"]
    trace = record["trace"]
    assert len(trace) == 7 and all(event["primaryCode"] == 0 for event in trace)
    assert [event["changes"] for event in trace] == [None, None, 1, 1, None, None, None]
    assert all(event["transactionOpen"] for event in trace[:5])
    assert all(event["persisted"] == record["initial"]["visible"] for event in trace[:5])
    assert table_values(trace[2]["visible"], "transient") == [((1, 9),)]
    assert decode_rows([trace[3]["parameters"]]) == [((1, 4), (3, b"seed"))]
    assert decode_rows(trace[4]["rows"]) == [((3, b"seed"), (1, 4))]
    assert not trace[5]["transactionOpen"]
    assert trace[5]["visible"] == trace[5]["persisted"] == record["initial"]["visible"]
    assert decode_rows(trace[6]["rows"]) == [((3, b"seed"), (1, 2))]


def test_savepoint_rollback_preserves_outer_prefix(transactions: dict[str, dict[str, Json]]) -> None:
    """ROLLBACK TO removes inner writes and schema changes; RELEASE leaves the outer transaction open."""
    record = transactions["immediate-savepoint-rollback"]
    trace = record["trace"]
    assert len(trace) == 12 and all(event["primaryCode"] == 0 for event in trace)
    assert [event["changes"] for event in trace] == [None, 1, None, None, 1, 1, None, None, None, None, None, None]
    assert all(event["transactionOpen"] for event in trace[:10])
    assert all(event["persisted"] == record["initial"]["visible"] for event in trace[:10])
    assert trace[7]["visible"] == trace[8]["visible"] == trace[1]["visible"]
    assert decode_rows(trace[6]["rows"]) == [((3, b"discarded"), (1, 8), (3, b"temporary")),
        ((3, b"kept"), (1, 5), (3, b"temporary")), ((3, b"seed"), (1, 6), (3, b"temporary"))]
    expected = [((3, b"kept"), (1, 5)), ((3, b"seed"), (1, 2))]
    assert decode_rows(trace[9]["rows"]) == decode_rows(trace[11]["rows"]) == expected
    assert not trace[10]["transactionOpen"]
    assert trace[10]["visible"] == trace[10]["persisted"] == trace[9]["visible"]


@pytest.mark.parametrize("name,extended,changes", [
    ("immediate-check-abort", 275, 0), ("immediate-deferred-commit-failure", 787, None),
])
def test_first_failure_retains_uncommitted_prefix(transactions: dict[str, dict[str, Json]],
                                                 name: str, extended: int, changes: int | None) -> None:
    """A failed statement or COMMIT leaves the group open and never executes the remaining SQL."""
    record = transactions[name]
    trace = record["trace"]
    assert len(trace) == 4 and all(event["primaryCode"] == 0 for event in trace[:3])
    failure = trace[-1]
    assert failure["primaryCode"] == 19 and failure["extendedCode"] == extended
    assert failure["changes"] == changes and failure["transactionOpen"]
    assert failure["visible"] == trace[2]["visible"]
    assert all(event["persisted"] == record["initial"]["visible"] for event in trace)
    if name == "immediate-check-abort":
        assert decode_rows([failure["parameters"]]) == [
            ((3, b"partial"), (1, 9), (3, b"bad"), (1, 0))]
        assert table_values(failure["visible"], "ledger") == [((3, b"seed"), (1, 2)), ((3, b"kept"), (1, 5))]
    else:
        assert record["profile"]["foreignKeys"]
        assert failure["sql"].strip() == "COMMIT;"
        assert table_values(failure["visible"], "parent") == []
        assert table_values(failure["visible"], "child") == [((1, 10), (1, 1))]
        assert table_values(failure["persisted"], "child") == []
