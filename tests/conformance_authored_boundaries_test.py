"""Native issue boundaries become corpus evidence, never new model support."""

import json
from pathlib import Path

import pytest

from conformance.authored_boundaries import definitions, validity_definitions
from conformance.authored_cases import records
from conformance.case_format import Json
from conformance.corpus import native_replay, replay
from conformance.native_record import record_sql
from conformance.native_bindings import decode_rows
from conformance.native_replay import prepare
from conformance.native_storage import CASE_BYTE_LIMIT, expanded_record, serialized, shared_record
from conformance.requirement_coverage import resolved_ids

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite-parser")]


@pytest.fixture(scope="module")
def boundaries() -> dict[str, dict[str, Json]]:
    """Acquire the 23 cases once; the native executor bounds each SQL call at five seconds."""
    acquired = records(definitions())
    assert len(acquired) == len({record["name"] for record in acquired}) == 23
    return {record["name"]: record for record in acquired}


def test_explicit_catalog_native_replay_and_classification(boundaries: dict[str, dict[str, Json]],
                                                         runtime_root: Path) -> None:
    """Profiles, outputs, requirement tags and bounded shared storage survive fresh replay."""
    catalog = list(boundaries.values())
    inventory = json.loads((Path(__file__).resolve().parents[1] /
                           "conformance/requirements-3.51.0.json").read_text())
    resolved_ids(catalog, inventory)
    for record in catalog:
        assert record["nativeVersion"] == 4 and record["features"]
        assert len(serialized(record)) < CASE_BYTE_LIMIT
        assert expanded_record(shared_record(record)) == record
        assert record["profile"]["engineVersion"] == "3.51.0"
    native_replay(catalog)
    assert replay(catalog, runtime_root)["counts"] == {"MODEL_UNSUPPORTED": 23}


def test_added_default_values_and_affinity(boundaries: dict[str, dict[str, Json]]) -> None:
    """Old rows and omitted INSERT columns read the same affinity-converted constant defaults."""
    trace = boundaries["add-default-storage-classes"]["trace"]
    values = ((5, None), (1, 300000), (2, 0x3FF0000000000000), (3, b"42"),
              (4, b"\x00\xff"), (2, 0x3FF8000000000000), (3, b"open"), (1, 42), (1, -7))
    assert len(trace) == 12 and all(event["primaryCode"] == 0 for event in trace)
    assert decode_rows(trace[9]["rows"]) == [((1, 7),) + values]
    assert decode_rows(trace[10]["rows"]) == [((1, 8),) + values]
    assert decode_rows([trace[10]["parameters"]]) == [((1, 8),)]
    assert [event["changes"] for event in trace] == [None] * 10 + [1, None]
    kinds = (b"null", b"integer", b"real", b"text", b"blob", b"real", b"text", b"integer", b"integer")
    assert decode_rows(trace[11]["rows"]) == [((1, value),) + tuple((3, kind) for kind in kinds)
        for value in (7, 8)]
    table = trace[-1]["visible"]["tables"][0]
    assert len(table["rows"]) == 2
    assert decode_rows(table["columns"])[7][3:5] == ((1, 1), (3, b"'open'"))


def test_not_null_add_depends_on_existing_rows(boundaries: dict[str, dict[str, Json]]) -> None:
    """Both implicit and explicit NULL defaults allow empty ADD but reject populated ADD."""
    for suffix in ("", "null-"):
        accepted = boundaries["add-not-null-" + suffix + "empty"]["trace"]
        assert [event["primaryCode"] for event in accepted] == [0, 0]
        assert accepted[1]["columns"] == ["a", "v"] and accepted[1]["rows"] == []
        table = accepted[-1]["visible"]["tables"][0]
        assert decode_rows(table["columns"])[1][3] == (1, 1) and not table["rows"]
        rejected = boundaries["add-not-null-" + suffix + "populated"]
        failed = rejected["trace"][0]
        assert len(rejected["trace"]) == 1 and failed["primaryCode"] == 1
        assert "NOT NULL column" in failed["error"] and failed["changes"] is None
        assert failed["visible"] == rejected["initial"]["visible"]
    inserted = boundaries["add-not-null-empty-insert"]["trace"]
    assert [event["primaryCode"] for event in inserted] == [0, 19]
    assert inserted[1]["changes"] == 0 and inserted[1]["visible"] == inserted[0]["visible"]


def test_rejected_add_forms_leave_schema_and_rows_unchanged(boundaries: dict[str, dict[str, Json]]) -> None:
    """Native failures retain the old table, including profile-dependent REFERENCES rejection."""
    errors = {"primary-key": "PRIMARY KEY", "unique": "UNIQUE", "stored": "STORED",
              "expression": "non-constant default", "references": "REFERENCES",
              "current-timestamp": "non-constant default"}
    for suffix, message in errors.items():
        record = boundaries["add-rejected-" + suffix]
        assert len(record["trace"]) == 1
        event = record["trace"][0]
        assert event["primaryCode"] == 1 and message in event["error"]
        assert event["visible"] == event["persisted"] == record["initial"]["visible"]
    assert boundaries["add-rejected-references"]["profile"]["foreignKeys"]
    assert boundaries["add-rejected-current-timestamp"]["trace"][0]["clockUnixMilliseconds"] == 1700000000000


def test_native_valid_definitions_have_concrete_rows(boundaries: dict[str, dict[str, Json]]) -> None:
    """Subset restrictions cannot turn engine-accepted definitions into native failures."""
    expected = {"empty-column-name": [((3, b"value"),)], "rowid-shadow": [((1, 9), (3, b"alias"), (1, 1))],
        "repeated-primary-key": [((1, 7), (3, b"key"))],
        "repeated-unique-key": [((5, None),), ((5, None),)],
        "repeated-index-column": [((1, 7),)], "identifier-case": [((1, 7),)],
        "integer-primary-key-sequence": [((3, b"t"), (1, 1))]}
    for suffix, rows in expected.items():
        trace = boundaries["validity-" + suffix]["trace"]
        assert all(event["primaryCode"] == 0 for event in trace)
        assert decode_rows(trace[-1]["rows"]) == rows
    shadow = boundaries["validity-rowid-shadow"]["trace"][-1]["visible"]["tables"][0]
    assert shadow["rowKey"] == ["_rowid_"]
    assert decode_rows([shadow["rows"][0]["identity"]]) == [((1, 1),)]
    mixed = boundaries["validity-identifier-case"]["trace"][-1]
    assert mixed["columns"] == ["Bar"] and mixed["visible"]["tables"][0]["name"] == "Foo"
    sequence = boundaries["validity-integer-primary-key-sequence"]["trace"]
    assert decode_rows(sequence[2]["rows"]) == [((1, 1), (3, b"value"))]
    assert {table["name"] for table in sequence[-1]["visible"]["tables"]} == {"t", "sqlite_sequence"}


def test_native_invalid_definitions_are_real_errors(boundaries: dict[str, dict[str, Json]]) -> None:
    """SQLITE_ERROR arises before a table appears; it is not manufactured by model admission."""
    for suffix, message in {"no-columns": "syntax error", "duplicate-column": "duplicate column",
                            "missing-key-column": "no such column", "reserved-name": "reserved"}.items():
        record = boundaries["validity-" + suffix]
        assert len(record["trace"]) == 1
        event = record["trace"][0]
        assert event["primaryCode"] == 1 and message in event["error"]
        assert event["visible"] == event["persisted"] == record["initial"]["visible"]
        assert event["visible"]["tables"] == []


def test_validity_boundaries_are_unsupported_without_profile_gate(runtime_root: Path) -> None:
    """Fresh implicit-profile records also reject subset boundaries, independently of C1 capability."""
    for case in validity_definitions():
        record = record_sql(case.setup, case.sql, name=case.name, outputs=True,
            parameters=list(case.parameters) if case.parameters is not None else None)
        model, answer = prepare(record, runtime_root / "build/sqlite-parser")
        assert model is None and answer["verdict"] == "MODEL_UNSUPPORTED", case.name
        if case.name == "validity-rowid-shadow":
            assert "rowid-shadowing names" in answer["error"]
