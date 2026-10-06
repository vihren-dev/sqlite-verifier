"""Keep source call evidence and replay inputs paired through native prefix minimization."""

from conformance.case_format import Json
from conformance.native_bindings import BINDING_NATIVE_VERSIONS, TCL_SQL_HELPERS, checked_binding, checked_call, call_slots, check_source_digest, check_source_results, decode_rows
from conformance.native_connection import Row
from conformance.upstream_helpers import command_events, command_ranges, join_commands

#: The complete extension includes replay guards as well as original source call references.
FIELDS = {"bindingRecordingVersion", "bindingRecordingKind", "setupBindings",
          "sourceCalls", "sourceSetupCommands", "setupCallIndices", "setupHelpers",
          "migrationReadonly", "migrationReadonlySpans", "auxiliaryReplay"}


def control(value: Json) -> bool:
    """Recognize the two retained connection operations without confusing booleans with integers."""
    return (value == {"reopen": True} and type(value.get("reopen")) is bool or
        isinstance(value, dict) and set(value) == {"dbConfig"} and isinstance(value["dbConfig"], list)
        and len(value["dbConfig"]) == 2 and all(type(item) is int for item in value["dbConfig"]))


def source_setup(record: dict[str, Json]) -> list[dict[str, Json] | None]:
    """Select current setup calls while retaining every original source call unchanged."""
    calls = record["sourceCalls"]["setup"]
    return [calls[index] for index in record["setupCallIndices"]]


def new_recording(setup: str | list[str | dict[str, Json]], migration: str,
                  calls: dict[str, Json] | None, explicit: bool,
                  indices: list[int] | None, original: list[str | dict[str, Json]] | None) -> dict[str, Json] | None:
    """The new binding transport is independent of output/profile acquisition versions."""
    if calls is None and not explicit:
        if indices is not None or original is not None:
            raise ValueError("Source setup references require retained Tcl calls")
        return None
    result: dict[str, Json] = {"bindingRecordingVersion": 1,
        "bindingRecordingKind": "tcl" if calls is not None else "explicit", "setupBindings": []}
    if calls is not None:
        commands = [setup] if isinstance(setup, str) else setup
        originals = commands if original is None else original
        result.update(sourceCalls=calls, sourceSetupCommands=originals,
                      setupCallIndices=list(range(len(commands))) if indices is None else indices)
        validate_sources({**result, "setupCommands": commands, "migrationSql": migration})
    return result


def validate_sources(record: dict[str, Json]) -> None:
    """Bind call indices to original SQL/control inputs and preserve the original assertion boundary."""
    calls, original, indices = record["sourceCalls"], record["sourceSetupCommands"], record["setupCallIndices"]
    if (not isinstance(calls, dict) or set(calls) != {"version", "setup", "assertion"}
            or type(calls["version"]) is not int or calls["version"] != 1
            or not isinstance(calls["setup"], list) or not isinstance(calls["assertion"], list)
            or not isinstance(original, list) or len(original) != len(calls["setup"])
            or not isinstance(indices, list) or len(indices) != len(record["setupCommands"])
            or any(type(index) is not int or not 0 <= index < len(original) for index in indices)
            or indices != sorted(set(indices))):
        raise ValueError("Invalid retained Tcl source call references")
    for command, call in zip(original, calls["setup"], strict=True):
        if isinstance(command, str):
            if checked_call(call)["sql"] != command:
                raise ValueError("Tcl setup source SQL differs")
        elif not control(command) or call is not None:
            raise ValueError("Tcl setup control evidence differs")
    if [original[index] for index in indices] != record["setupCommands"]:
        raise ValueError("Tcl setup source references differ from replay inputs")
    assertion = [checked_call(call) for call in calls["assertion"]]
    if join_commands([call["sql"] for call in assertion]) != record["migrationSql"]:
        raise ValueError("Tcl assertion call source differs from replay SQL")


def recording_inputs(setup: str | list[str | dict[str, Json]], migration: str,
                     calls: dict[str, Json] | None, parameters: list[list[Row]] | None,
                     indices: list[int] | None, original: list[str | dict[str, Json]] | None,
                     outputs: bool, names: list[list[list[str | None]]] | None,
                     statement_names: list[list[str | None]] | None) -> tuple[
                         str | list[str | dict[str, Json]], dict[str, Json] | None,
                         list[dict[str, Json] | None] | None]:
    """Check input alignment before opening a native database or running setup SQL."""
    recording = new_recording(setup, migration, calls, parameters is not None, indices, original)
    if recording is not None:
        if not outputs:
            raise ValueError("Setup and Tcl bindings require output recording")
        setup = [setup] if isinstance(setup, str) else setup
        if parameters is not None and len(parameters) != len(setup) or names is not None and len(names) != len(setup):
            raise ValueError("Expected one binding input list per setup command")
        for index, command in enumerate(setup):
            if isinstance(command, dict) and (parameters is not None and parameters[index] or
                                             names is not None and names[index]):
                raise ValueError("Setup controls cannot have statement bindings")
    elif names is not None or statement_names is not None:
        raise ValueError("Recorded slot names require binding recording inputs")
    return setup, recording, source_setup(recording) if calls is not None else None


def validate_call_bindings(call: dict[str, Json], events: list[dict[str, Json]]) -> None:
    """Every recorded slot has its observed source value, and every observed slot was reached."""
    values, reached = call_slots(call), set()
    for event in events:
        names, bound = checked_binding({key: event[key] for key in ("parameterNames", "parameters")})
        if any(name is None or name not in values for name in names):
            raise ValueError("Tcl parameter slot has no observed value")
        if tuple(values[name] for name in names) != bound:
            raise ValueError("Recorded parameters differ from the Tcl call bindings")
        reached.update(names)
    if reached != set(values):
        raise ValueError("Tcl binding metadata contains an unreached parameter")


def validate_recording(record: dict[str, Json]) -> None:
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
        raise ValueError("Invalid native binding recording version or fields")
    helpers, spans = record["setupHelpers"], record["migrationReadonlySpans"]
    if (not isinstance(helpers, list) or len(helpers) != len(record["setupCommands"])
            or any(not isinstance(helper, str) or helper not in TCL_SQL_HELPERS for helper in helpers)
            or any(type(record[key]) is not bool for key in ("migrationReadonly", "auxiliaryReplay"))
            or not isinstance(spans, list) or any(not isinstance(span, list) or len(span) != 2
                or any(type(value) is not int for value in span)
                or not 0 <= span[0] <= span[1] <= len(record["migrationSql"].encode()) for span in spans)):
        raise ValueError("Invalid native binding replay guards")
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


def replay_arguments(record: dict[str, Json]) -> dict[str, Json]:
    """Supply exact setup vectors and call references to the single native recorder."""
    validate_recording(record)
    if "bindingRecordingVersion" not in record:
        return {}
    result = {"setup_parameters": [decode_rows([event["parameters"] for event in events])
                                  for events in record["setupBindings"]],
        "setup_parameter_names": [[event["parameterNames"] for event in events]
                                  for events in record["setupBindings"]],
        "parameter_names": [event["parameterNames"] for event in record["trace"]]}
    result.update(setup_helpers=record["setupHelpers"], migration_readonly=record["migrationReadonly"],
                  migration_readonly_spans=[tuple(span) for span in record["migrationReadonlySpans"]],
                  auxiliary_replay=record["auxiliaryReplay"])
    if record["bindingRecordingKind"] == "tcl":
        result.update(tcl_calls=record["sourceCalls"], source_setup_commands=record["sourceSetupCommands"],
                      setup_call_indices=record["setupCallIndices"])
    return result


def reached_call(sql: str, remaining: bytes, calls: list[dict[str, Json]]) -> tuple[int, dict[str, Json] | None]:
    """Use original UTF-8 call spans to select the observed environment before preparation."""
    from conformance.query_window import tokens
    source = remaining.decode()
    lexical = [token for token in tokens(source) if token.text != ";"]
    if not lexical:
        return -1, None
    offset = len(sql.encode()) - len(remaining) + (len(source[:lexical[0].start].encode()) if lexical else 0)
    index = next((index for index, (start, end) in enumerate(command_ranges([call["sql"] for call in calls]))
                  if start <= offset < end), None)
    if index is None:
        raise ValueError("Native statement has no original Tcl call boundary")
    return index, calls[index]


def check_call_end(sql: str, remaining: bytes, consumed: bytes, index: int,
                   calls: list[dict[str, Json]]) -> None:
    """Refuse a statement that SQLite parsed across an original Tcl call boundary."""
    from conformance.query_window import tokens
    lexical = [token for token in tokens(consumed.decode()) if token.text != ";"]
    if lexical and len(sql.encode()) - len(remaining) + len(consumed.decode()[:lexical[-1].end].encode()) > (
            command_ranges([call["sql"] for call in calls])[index][1]):
        raise ValueError("Native statement crosses Tcl SQL call boundary")
