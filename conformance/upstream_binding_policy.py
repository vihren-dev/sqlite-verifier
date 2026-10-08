"""Bind observed Tcl call inputs to versioned acquisition and frozen source evidence."""

import hashlib
import re

from conformance.case_format import Json
from conformance.native_storage import serialized
from conformance.upstream_bindings import named_slots


def binding_policy() -> dict[str, Json]:
    """Declare actual Tcl object observation and native SQLite slot verification for new evidence."""
    return {"version": 1, "observer": "tcl-scalar-objects-v1", "slots": "sqlite-bind-parameter-v1"}


def retained_binding_policy(report: dict[str, Json]) -> bool:
    """Version two requires complete call evidence; historical version one keeps its refusal boundary."""
    version = report.get("corpusVersion")
    if type(version) is not int or version not in {1, 2}:
        raise ValueError("Unsupported retained acquisition version")
    if version == 1:
        if "tclBindingPolicy" in report:
            raise ValueError("Historical acquisition cannot declare Tcl binding observation")
        return False
    if serialized(report.get("tclBindingPolicy")) != serialized(binding_policy()):
        raise ValueError("Missing or invalid retained Tcl binding policy")
    return True


def call_digest(instance: dict[str, Json], *, required: bool) -> str | None:
    """Bind source-call input identities independently of regenerated transport digests."""
    value = instance.get("tclCallsSha256")
    if value is None and not required:
        return None
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise ValueError("Missing or invalid retained Tcl call digest")
    return value


def retained_call_evidence(record: dict[str, Json], instance: dict[str, Json], *, observed: bool,
                           precision: Json, nullvalue: Json) -> None:
    """Keep every accepted call linked to its observed source values and formatting conditions."""
    if not observed:
        if ("bindingRecordingVersion" in record or call_digest(instance, required=False) is not None
                or any(named_slots(command) for command in record["setupCommands"] + [record["migrationSql"]]
                       if isinstance(command, str))):
            raise ValueError("Historical acquisition contains unobserved Tcl bindings")
        return
    expected = call_digest(instance, required=True)
    calls = record.get("sourceCalls")
    if (record.get("bindingRecordingKind") != "tcl" or not isinstance(calls, dict)
            or hashlib.sha256(serialized(calls)).hexdigest() != expected
            or record["upstream"].get("tclCallsSha256") != expected):
        raise ValueError("Retained Tcl call source binding differs")
    successful = [call for call in calls["setup"] + calls["assertion"]
                  if call is not None and call["code"] == 0]
    for field, evidence in (("precision", precision), ("nullValue", nullvalue)):
        values = [call[field] for call in successful]
        summary = {"values": sorted(set(values), key=lambda value: (value is not None, value)),
                   "successfulCalls": len(values)}
        if serialized(summary) != serialized(evidence):
            raise ValueError("Retained Tcl call display evidence differs")


def validate_capture_bindings(manifest: dict[str, Json], records: list[dict[str, Json]]) -> None:
    """Direct capture loading enforces observed inputs even without catalog profiles or a later freeze."""
    if "files" not in manifest or "extractorSha256" not in manifest:
        return
    observed = retained_binding_policy(manifest)
    if not observed:
        for record in records:
            source = record.get("upstream", {})
            if ("bindingRecordingVersion" in record or "tclCallsSha256" in source
                    or any(named_slots(command) for command in record["setupCommands"] + [record["migrationSql"]]
                           if isinstance(command, str))):
                raise ValueError("Historical capture contains unobserved Tcl binding evidence")
        return
    files = manifest["files"]
    if not isinstance(files, list):
        raise ValueError("Invalid Tcl capture source files")
    accepted: dict[tuple[str, str, int], dict[str, Json]] = {}
    for file in files:
        if not isinstance(file, dict) or not isinstance(file.get("file"), str):
            raise ValueError("Invalid Tcl capture source file")
        instances = file.get("instances", [])
        if not isinstance(instances, list):
            raise ValueError("Invalid Tcl capture instances")
        for occurrence, instance in enumerate(instances):
            if (not isinstance(instance, dict) or not isinstance(instance.get("id"), str)
                    or type(instance.get("occurrence")) is not int or instance["occurrence"] != occurrence
                    or not isinstance(instance.get("exclusions"), list)):
                raise ValueError("Invalid Tcl capture instance")
            call_digest(instance, required=observed and not instance["exclusions"])
            if not instance["exclusions"]:
                key = file["file"], instance["id"], occurrence
                if key in accepted:
                    raise ValueError("Duplicate Tcl capture source identity")
                accepted[key] = instance
    seen: set[tuple[str, str, int]] = set()
    for record in records:
        source = record.get("upstream")
        if (not isinstance(source, dict) or not isinstance(source.get("file"), str)
                or not isinstance(source.get("id"), str) or type(source.get("occurrence")) is not int):
            raise ValueError("Missing Tcl capture source identity")
        key = source["file"], source["id"], source["occurrence"]
        if key not in accepted or key in seen:
            raise ValueError("Tcl capture accepted membership differs")
        if observed:
            digest = call_digest(accepted[key], required=True)
            if (record.get("bindingRecordingKind") != "tcl"
                    or source.get("tclCallsSha256") != digest
                    or hashlib.sha256(serialized(record.get("sourceCalls"))).hexdigest() != digest):
                raise ValueError("Tcl capture call evidence differs from its source instance")
        elif "bindingRecordingVersion" in record or "tclCallsSha256" in source:
            raise ValueError("Historical capture contains new Tcl binding evidence")
        seen.add(key)
    if seen != set(accepted):
        raise ValueError("Tcl capture accepted membership differs")
