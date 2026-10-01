"""Neutral cases retain concrete SQL behavior before production model extension."""

from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path

import pytest

from conformance.authored_cases import records
from conformance.case_format import Json
from conformance.corpus import native_replay, replay
from conformance.execution_profile import validate_manifest_profiles
from conformance.native_replay import decode_rows, output_wire
from conformance.native_storage import CASE_BYTE_LIMIT, expanded_record, serialized, shared_record
from conformance.requirement_cases import definitions as requirement_definitions
from conformance.requirement_coverage import comparison

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/20261001-adr5-c5-authored.json"
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite-parser")]


@pytest.fixture(scope="module")
def authored() -> dict[str, dict[str, Json]]:
    """Acquire the catalog once; each case uses independent native connections."""
    acquired = records()
    assert len({record["name"] for record in acquired}) == len(acquired) == 43
    return {record["name"]: record for record in acquired}


def table_rows(event: dict[str, Json], name: str, *, persisted: bool = False) -> list[Json]:
    """Read the recorded table by name so schema inventory ordering cannot hide a wrong row."""
    table = next(table for table in event["persisted" if persisted else "visible"]["tables"]
                 if table["name"] == name)
    return table["rows"]


def test_catalog_keeps_legacy_sql_and_complete_outputs(authored: dict[str, dict[str, Json]],
                                                      runtime_root: Path) -> None:
    """Legacy scenarios gain evidence; explicit profiles cannot produce false model agreements."""
    for name, setup, sql, tags in requirement_definitions():
        record = authored[name]
        assert (record["setupSql"], record["migrationSql"], record["requirements"]) == (setup, sql, tags)
        assert record["part"] == "requirement"
    for record in authored.values():
        assert record["nativeVersion"] == 4 and record["features"]
        assert len(serialized(record)) <= CASE_BYTE_LIMIT
        assert expanded_record(shared_record(record)) == record
        for event in record["trace"]:
            output_wire(event)
            assert event["columnCount"] == len(event["columns"])
    result = replay(list(authored.values()), runtime_root)
    assert result["counts"] == {"MODEL_UNSUPPORTED": 43}


def test_retained_authored_evidence_and_coverage(authored: dict[str, dict[str, Json]]) -> None:
    """The report binds actual native evidence and counts its measured membership once."""
    from conformance.corpus import load
    report = json.loads(REPORT.read_text())
    evidence = REPORT.with_name(report["authoredEvidence"]["file"])
    payload = gzip.decompress(evidence.read_bytes())
    assert hashlib.sha256(payload).hexdigest() == report["authoredEvidence"]["casesSha256"]
    frozen = [expanded_record(json.loads(line)) for line in payload.splitlines()]
    assert {record["name"]: record for record in frozen} == authored
    validate_manifest_profiles(report["authoredEvidence"], frozen)
    native_replay(frozen)
    manifest, previous = load(ROOT / "conformance/corpus-v3")
    inventory_path = ROOT / "conformance/requirements-3.51.0.json"
    assert report["baseline"]["casesSha256"] == manifest["casesSha256"]
    assert report["requirementsSha256"] == hashlib.sha256(inventory_path.read_bytes()).hexdigest()
    after = [record for record in previous if record["name"] not in authored] + frozen
    assert report["coverage"] == comparison(previous, after, json.loads(inventory_path.read_text()))
    assert report["replacementCases"] == 29 and report["newCases"] == 14
    assert report["modelClassification"]["counts"] == {"MODEL_UNSUPPORTED": 43}
    corrupted = deepcopy(authored["upsert-returning"])
    corrupted["trace"][0]["changes"] = 9
    with pytest.raises(ValueError, match="Native replay changed"):
        native_replay([corrupted])


def test_bound_storage_classes_and_integer_edges(authored: dict[str, dict[str, Json]]) -> None:
    """Binding preserves empty bytes, embedded NUL, REAL bits and both signed integer limits."""
    trace = authored["typed-values-edges"]["trace"]
    cells = [(5, None), (1, -(2**63)), (1, 2**63 - 1), (2, 0x3FF8000000000000),
             (3, b""), (3, b"caf\xc3\xa9\x00"), (4, b""), (4, b"\x00\xff")]
    assert decode_rows(trace[0]["rows"]) == [(cell,) for cell in cells]
    assert trace[0]["parameters"] == [row[0] for row in trace[0]["rows"]]
    assert trace[0]["changes"] == 8 and trace[0]["groups"] is None
    kinds = (b"null", b"integer", b"integer", b"real", b"text", b"text", b"blob", b"blob")
    assert decode_rows(trace[1]["rows"]) == [((1, index), cell, (3, kind))
        for index, (cell, kind) in enumerate(zip(cells, kinds, strict=True), 1)]
    assert trace[1]["changes"] is None


def test_defaults_and_added_column(authored: dict[str, dict[str, Json]]) -> None:
    """Omitted columns use their defaults and ALTER preserves the existing row."""
    trace = authored["schema-defaults-add"]["trace"]
    assert decode_rows(trace[0]["rows"]) == [((3, b"key"), (3, b"new"), (5, None))]
    assert decode_rows(trace[3]["rows"]) == [((3, b"key"), (3, b"new"), (5, None), (3, b""))]
    assert [event["changes"] for event in trace] == [1, None, None, None]
    assert len(table_rows(trace[-1], "t")) == 1
    assert any(decode_rows([row])[0][1] == (3, b"by_label") for row in trace[-1]["visible"]["schema"])


def test_transaction_trigger_cascade_and_direct_counts(authored: dict[str, dict[str, Json]]) -> None:
    """Direct counts exclude four trigger rows and two cascades; COMMIT publishes the writes."""
    record = authored["transaction-trigger-cascade-counts"]
    trace = record["trace"]
    assert record["profile"]["foreignKeys"] and record["profile"]["transactionMode"] == "immediate"
    assert [event["changes"] for event in trace] == [None, 2, 2, 1, None, 0, 1, None, None, None]
    assert decode_rows(trace[1]["rows"]) == [((1, 2),), ((1, 3),)]
    assert trace[4]["columns"] == ["missing"] and trace[4]["rows"] == []
    assert decode_rows(trace[6]["rows"]) == [((1, 2),)]
    assert table_rows(trace[6], "child") == [] and len(table_rows(trace[6], "audit")) == 4
    assert all(event["persisted"] == record["initial"]["visible"] for event in trace[:8])
    assert all(event["transactionOpen"] for event in trace[:8])
    assert not trace[8]["transactionOpen"] and trace[8]["visible"] == trace[8]["persisted"]
    assert decode_rows(trace[9]["rows"]) == [((1, 3),)]


def test_upsert_all_returning_branches(authored: dict[str, dict[str, Json]]) -> None:
    """Insert/update return their direct row; DO NOTHING retains shape with zero changes."""
    trace = authored["upsert-returning"]["trace"]
    assert [decode_rows(event["rows"]) for event in trace] == [
        [((3, b"a"), (1, 1))], [((3, b"a"), (1, 2))], []]
    assert [event["changes"] for event in trace] == [1, 1, 0]
    assert trace[2]["columns"] == ["id", "v"] and trace[2]["groups"] is None
    assert trace[2]["visible"] == trace[1]["visible"]


def test_constraint_failures_and_statement_rollback(authored: dict[str, dict[str, Json]]) -> None:
    """ABORT removes the failing statement's writes while preserving earlier transaction rows."""
    record = authored["check-abort"]
    failed = record["trace"][-1]
    assert len(record["trace"]) == 3 and failed["primaryCode"] == 19 and failed["changes"] == 0
    assert failed["transactionOpen"] and failed["persisted"] == record["initial"]["visible"]
    assert decode_rows([row["values"] for row in table_rows(failed, "t")]) == [((1, 1), (5, None))]
    for name in ("text-primary-key-failure", "not-null-failure", "foreign-key-failure"):
        record = authored[name]
        assert len(record["trace"]) == 1 and record["trace"][0]["primaryCode"] == 19
        assert record["trace"][0]["changes"] == 0
        assert record["trace"][0]["visible"] == record["initial"]["visible"]
    assert authored["foreign-key-failure"]["profile"]["foreignKeys"]
