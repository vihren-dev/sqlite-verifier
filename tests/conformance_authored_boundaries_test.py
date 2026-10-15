"""Native issue boundaries become corpus evidence, never new model support."""

import json
from pathlib import Path

import pytest

from conformance.authored_boundaries import definitions, validity_definitions
from conformance.authored_cases import records
from conformance.case_format import Json
from conformance.corpus import native_replay, replay
from conformance.native_record import record_sql
from conformance.model_check import compiled
from conformance.native_replay import prepare
from conformance.native_storage import CASE_BYTE_LIMIT, expanded_record, serialized, shared_record
from conformance.requirement_coverage import resolved_ids
from conformance.record_parser import runtime_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "parser-library")]


@pytest.fixture(scope="module")
def boundaries() -> dict[str, dict[str, Json]]:
    """Acquire the 23 cases once; the native executor bounds each SQL call at five seconds."""
    acquired = records(definitions())
    assert len(acquired) == len({record["name"] for record in acquired}) == 23
    return {record["name"]: record for record in acquired}


def test_explicit_catalog_native_replay_and_classification(boundaries: dict[str, dict[str, Json]],
                                                         runtime_root: Path) -> None:
    """Profiles, outputs, requirement tags and bounded shared storage survive fresh replay. The
    model implements the default execution settings of these profiles (`profile_scope`), so the
    cases whose SQL it models agree, including NOT NULL additions on empty and
    populated tables, and the others stay out of scope."""
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
    report = replay(catalog, runtime_root)
    assert report["counts"] == {"MODEL_UNSUPPORTED": 13, "AGREE": 10}
    additions = {"add-not-null-empty", "add-not-null-populated",
                 "add-not-null-null-empty", "add-not-null-null-populated"}
    assert {case["name"] for case in report["cases"]
            if case["name"] in additions and case["verdict"] == "AGREE"} == additions


def test_validity_boundaries_without_profile_gate(runtime_root: Path) -> None:
    """Fresh implicit-profile records: model boundaries stay unsupported, and SQLite's prepare errors agree.

    The native-valid cases use parameters or schemas outside the model, which the
    statement mapping or resolution refuses; a query on a table whose names differ
    only in case agrees (ADR 0012). A duplicate column, a missing key column and a
    reserved name are SQLite prepare errors that Lean resolution decides, so the
    model agrees with them; an empty column list is a grammar error on both sides.
    """
    agreeing = {"validity-duplicate-column", "validity-missing-key-column", "validity-reserved-name",
                "validity-identifier-case"}
    for case in validity_definitions():
        record = record_sql(case.setup, case.sql, name=case.name, outputs=True,
            parameters=list(case.parameters) if case.parameters is not None else None)
        model, answer = prepare(record, runtime_library(runtime_root))
        if case.name in agreeing:
            assert model is not None, (case.name, answer)
            assert compiled(model, runtime_root)["verdict"] == "AGREE", case.name
        else:
            verdict = compiled(model, runtime_root)["verdict"] if model is not None else answer["verdict"]
            assert verdict == "MODEL_UNSUPPORTED", case.name
