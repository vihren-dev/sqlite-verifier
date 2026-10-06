"""Authored query outputs preserve NULL, arithmetic, ties, clocks and JSON shape."""

import struct

import pytest

from conformance.case_format import Json
from conformance.native_connection import Cell
from conformance.native_replay import decode_rows
from tests.conformance_authored_test import authored, table_rows

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3")]


def real(value: float) -> Cell:
    """Assert the exact IEEE storage bits as well as the REAL storage class."""
    return (2, struct.unpack(">Q", struct.pack(">d", value))[0])


def test_aggregates_empty_single_and_null_groups(authored: dict[str, dict[str, Json]]) -> None:
    """Empty SUM/MAX/AVG stay NULL; COUNT and grouping distinguish rows from non-NULL values."""
    trace = authored["aggregates-empty-single-null-groups"]["trace"]
    assert decode_rows(trace[0]["rows"]) == [((1, 0), (1, 0), (5, None), (5, None), (5, None))]
    assert decode_rows(trace[2]["rows"]) == [((1, 1), (1, 1), (1, 2), real(2), (1, 2))]
    assert decode_rows(trace[4]["rows"]) == [((1, 5), (1, 3), (1, 7), real(7 / 3), (1, 4))]
    assert decode_rows(trace[5]["rows"]) == [
        ((5, None), (1, 2), (1, 1), (1, 4), real(4), (1, 4)),
        ((3, b""), (1, 1), (1, 1), (1, 1), real(1), (1, 1)),
        ((3, b"one"), (1, 2), (1, 1), (1, 2), real(2), (1, 2))]


def test_join_coalesce_cast_and_real_arithmetic(authored: dict[str, dict[str, Json]]) -> None:
    """LEFT JOIN adds the missing row; expression outputs retain NULL and REAL types."""
    trace = authored["join-coalesce-cast-real"]["trace"]
    assert decode_rows(trace[0]["rows"]) == [((1, 1), (5, None), (3, b"match"))]
    assert decode_rows(trace[1]["rows"]) == [
        ((1, 1), (5, None), (3, b"match"), (3, b"match")),
        ((1, 2), (3, b""), (5, None), (3, b""))]
    assert decode_rows(trace[2]["rows"]) == [((5, None), (3, b""), (1, -1), (5, None), real(3.5))]


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


def test_json_types_missing_paths_and_empty_shape(authored: dict[str, dict[str, Json]]) -> None:
    """JSON missing/null values agree while an empty array still has three output columns."""
    record = authored["json-values-empty"]
    assert record["requirements"] == [] and {"json_extract", "json_each"} <= set(record["features"])
    trace = record["trace"]
    assert decode_rows(trace[0]["rows"]) == [((1, 7), (5, None), (5, None))]
    assert decode_rows(trace[1]["rows"]) == [
        ((1, 0), (5, None), (3, b"null")), ((1, 1), (1, 0), (3, b"integer")),
        ((1, 2), (3, b""), (3, b"text")), ((1, 3), real(1.5), (3, b"real"))]
    assert trace[2]["columns"] == ["key", "value", "type"] and trace[2]["columnCount"] == 3
    assert trace[2]["rows"] == trace[2]["groups"] == [] and trace[2]["changes"] is None
