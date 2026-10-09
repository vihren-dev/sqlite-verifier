"""Immediate groups keep typed outputs and the observer of the open transaction."""

import pytest

from conformance.authored_cases import definitions as historical_definitions, records
from conformance.authored_boundaries import definitions as historical_boundaries
from conformance.authored_review import definitions as historical_review
from conformance.authored_transactions import definitions
from conformance.case_format import Json
from conformance.native_replay import output_wire

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture(scope="module")
def transactions() -> dict[str, dict[str, Json]]:
    """Acquire only new definitions; each native statement has the shared five-second deadline."""
    return {record["name"]: record for record in records(definitions())}


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
    assert all(event["transactionOpen"] for event in trace[:6])
    assert all(event["persisted"] == record["initial"]["visible"] for event in trace[:6])
    assert not trace[6]["transactionOpen"]
    assert trace[6]["visible"] == trace[6]["persisted"] == trace[5]["visible"]
    assert trace[6]["persisted"] != record["initial"]["visible"]
