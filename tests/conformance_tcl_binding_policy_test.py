"""Acquisition versions and source identities cannot lose observed binding evidence."""

from copy import deepcopy
import hashlib

import pytest

from conformance.case_format import Json
from conformance.native_record import record_sql
from conformance.native_storage import serialized
from conformance.native_call_recording import FIELDS, validate_recording
from conformance.upstream_binding_policy import (binding_policy, retained_binding_policy,
    retained_call_evidence, validate_capture_bindings)

pytestmark = [pytest.mark.conformance, pytest.mark.integration, pytest.mark.requires_native("sqlite3")]


def source_inputs() -> tuple[dict[str, Json], dict[str, Json], dict[str, Json]]:
    """Record a value-dependent native case and its original accepted source occurrence."""
    call: dict[str, Json] = {"sql": "SELECT $value", "helper": "eval", "code": 0,
        "results": ["7"], "precision": 0, "nullValue": "",
        "bindings": {"$value": {"integer": {"value": 7}}},
        "objects": {"$value": {"type": "int", "hasString": False}}}
    record = record_sql([], call["sql"], name="source-policy-case", outputs=True,
                        tcl_calls={"version": 1, "setup": [], "assertion": [call]})
    digest = hashlib.sha256(serialized(record["sourceCalls"])).hexdigest()
    record["upstream"] = {"file": "bindings.test", "id": "probe", "occurrence": 0, "tclCallsSha256": digest}
    instance: dict[str, Json] = {"id": "probe", "occurrence": 0, "result": "recorded",
                               "exclusions": [], "tclCallsSha256": digest}
    manifest: dict[str, Json] = {"corpusVersion": 2, "tclBindingPolicy": binding_policy(),
        "extractorSha256": {}, "files": [{"file": "bindings.test", "instances": [instance]}]}
    return manifest, record, instance


def test_current_call_identity_is_valid_before_damage() -> None:
    """The negative checks start with fresh evidence accepted by every binding policy guard."""
    manifest, record, instance = source_inputs()
    assert retained_binding_policy(manifest)
    validate_capture_bindings(manifest, [record])
    retained_call_evidence(record, instance, observed=True,
        precision={"values": [0], "successfulCalls": 1}, nullvalue={"values": [""], "successfulCalls": 1})


@pytest.mark.parametrize("damage", ["historical-policy", "missing-policy", "boolean-version",
    "relabel", "remove-extension", "remove-extension-and-digest", "historical-digest", "historical-version"])
def test_policy_relabeling_and_evidence_removal_are_refused(damage: str) -> None:
    """Changing transport declarations cannot reinterpret observed inputs as unbound historical SQL."""
    manifest, record, instance = source_inputs()
    if damage == "historical-policy":
        manifest["corpusVersion"] = 1
    elif damage == "missing-policy":
        del manifest["tclBindingPolicy"]
    elif damage == "boolean-version":
        manifest["corpusVersion"] = True
    elif damage in {"relabel", "historical-digest", "historical-version"}:
        manifest["corpusVersion"] = 1
        del manifest["tclBindingPolicy"]
        if damage != "historical-version":
            for field in FIELDS:
                record.pop(field, None)
            for event in record["trace"]:
                event.pop("parameterNames", None)
        if damage == "relabel":
            record["upstream"].pop("tclCallsSha256")
            instance.pop("tclCallsSha256")
    else:
        for field in FIELDS:
            record.pop(field, None)
        for event in record["trace"]:
            event.pop("parameterNames", None)
        if damage == "remove-extension-and-digest":
            record["upstream"].pop("tclCallsSha256")
    with pytest.raises(ValueError):
        validate_capture_bindings(manifest, [record])
    if damage in {"historical-policy", "missing-policy", "boolean-version"}:
        with pytest.raises(ValueError):
            retained_binding_policy(manifest)
    else:
        with pytest.raises(ValueError):
            retained_call_evidence(record, instance, observed=manifest["corpusVersion"] == 2,
                precision={"values": [0], "successfulCalls": 1}, nullvalue={"values": [""], "successfulCalls": 1})


def test_binding_diagnostic_identifies_case_field_and_recovery() -> None:
    """A corrupted guard reports its source case and a concrete recovery action."""
    _manifest, record, _instance = source_inputs()
    damaged = deepcopy(record)
    damaged["migrationReadonly"] = "true"
    with pytest.raises(ValueError) as failure:
        validate_recording(damaged)
    assert "source-policy-case" in str(failure.value)
    assert "migrationReadonly" in str(failure.value)
    assert "Capture this source case again" in str(failure.value)
