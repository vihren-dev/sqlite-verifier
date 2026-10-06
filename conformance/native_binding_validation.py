"""Validate complete binding evidence before model admission or native replay."""

from conformance.case_format import Json
from conformance.native_bindings import BINDING_NATIVE_VERSIONS, TCL_SQL_HELPERS, checked_binding, check_source_digest, check_source_results
from conformance.native_call_recording import FIELDS, control, source_setup, validate_sources, validate_call_bindings
from conformance.upstream_helpers import command_events


def validate_fields(record: dict[str, Json]) -> None:
    """Refuse incomplete new evidence before historical replay or unsupported admission."""
    present = FIELDS & record.keys()
    trace = record.get("trace", [])
    if not present:
        if (any(isinstance(event, dict) and "parameterNames" in event for event in trace)
                or isinstance(record.get("upstream"), dict) and "tclCallsSha256" in record["upstream"]):
            raise ValueError("Native slot names require a binding recording version")
        return
    version, kind = record.get("bindingRecordingVersion"), record.get("bindingRecordingKind")
    required = FIELDS if kind == "tcl" else FIELDS - {"sourceCalls", "sourceSetupCommands", "setupCallIndices"}
    if (type(version) is not int or version != 1 or not isinstance(kind, str) or kind not in {"tcl", "explicit"}
            or present != required or type(record.get("nativeVersion")) is not int
            or record["nativeVersion"] not in BINDING_NATIVE_VERSIONS
            or not isinstance(record.get("setupCommands"), list) or not isinstance(trace, list)
            or not isinstance(record.get("setupBindings"), list)
            or len(record["setupBindings"]) != len(record["setupCommands"])):
        raise ValueError("Invalid bindingRecordingVersion, bindingRecordingKind, nativeVersion or setupBindings fields")
    helpers, spans = record["setupHelpers"], record["migrationReadonlySpans"]
    if (not isinstance(helpers, list) or len(helpers) != len(record["setupCommands"])
            or any(not isinstance(helper, str) or helper not in TCL_SQL_HELPERS for helper in helpers)
            or any(type(record[key]) is not bool for key in ("migrationReadonly", "auxiliaryReplay"))
            or not isinstance(spans, list) or any(not isinstance(span, list) or len(span) != 2
                or any(type(value) is not int for value in span)
                or not 0 <= span[0] <= span[1] <= len(record["migrationSql"].encode()) for span in spans)):
        raise ValueError("Invalid setupHelpers, migrationReadonly, migrationReadonlySpans or auxiliaryReplay fields")
    check_source_digest(record)
    for command, events in zip(record["setupCommands"], record["setupBindings"], strict=True):
        if not isinstance(events, list) or not isinstance(command, str) and (not control(command) or events):
            raise ValueError("Invalid native setup binding inputs")
        for event in events:
            checked_binding(event)
    for event in trace:
        if not isinstance(event, dict) or "parameterNames" not in event or "parameters" not in event:
            raise ValueError("Missing native statement binding inputs")
        checked_binding({key: event[key] for key in ("parameterNames", "parameters")})
    if kind == "tcl":
        validate_sources(record)
        if helpers != [call["helper"] if call is not None else "eval" for call in source_setup(record)]:
            raise ValueError("Tcl setup helpers differ from source calls")
        for call, events in zip(source_setup(record), record["setupBindings"], strict=True):
            if call is not None:
                validate_call_bindings(call, events)
        calls = record["sourceCalls"]["assertion"]
        for call, events in zip(calls, command_events(record, [call["sql"] for call in calls]), strict=True):
            validate_call_bindings(call, events)
        check_source_results(record)

