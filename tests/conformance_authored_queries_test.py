"""Authored query records keep our tie groups and our deterministic clock."""

import pytest

from conformance.case_format import Json
from conformance.native_bindings import decode_rows
from tests.conformance_authored_test import authored, table_rows

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3")]


def test_numeric_and_nocase_boundary_groups(authored: dict[str, dict[str, Json]]) -> None:
    """A window can cut two groups or both ends of one group without inventing a row order."""
    record = authored["numeric-ties-windows"]
    trace = record["trace"]
    assert [[(group["count"], len(group["rows"])) for group in event["groups"]] for event in trace] == [
        [(1, 1), (3, 3), (1, 1), (2, 2)], [(2, 3), (1, 1), (1, 2)],
        [(1, 3)], [(2, 7)], []]
    numeric = decode_rows(trace[0]["groups"][1]["rows"])
    assert sorted(cell[0] for cell, _ in numeric) == [1, 1, 2]
    assert decode_rows(trace[0]["rows"])[0][0] == (5, None)
    assert all(event["visible"] == record["initial"]["visible"] for event in trace)
    distinct = authored["ordered-distinct-nocase"]["trace"]
    assert len(distinct[0]["rows"]) == 3 and len(distinct[1]["rows"]) == 2
    assert [[(group["count"], len(group["rows"])) for group in event["groups"]]
            for event in distinct] == [[(1, 1), (2, 2)], [(1, 1), (1, 2)]]
    assert set(decode_rows(distinct[0]["groups"][1]["rows"])) == {((3, b"a"),), ((3, b"A"),)}


def test_clock_defaults_triggers_and_same_statement_now(authored: dict[str, dict[str, Json]]) -> None:
    """Defaults and triggers see the write clock; the ordered probe sees the query clock."""
    trace = authored["clock-format-default-trigger"]["trace"]
    assert [event["clockUnixMilliseconds"] for event in trace] == [
        1700000000000, 1700000001000, 1700000002000, 1700000003000]
    expected = ((3, b"2023-11-14 22:13:21"), (1, 1700000001))
    assert decode_rows(trace[1]["rows"]) == [expected]
    assert decode_rows([row["values"] for row in table_rows(trace[1], "audit")]) == [expected]
    assert decode_rows(trace[2]["rows"]) == [expected + (
        (1, 1700000002), (1, 1700000002), (3, b"2023-11-14 22:13:22"))]
