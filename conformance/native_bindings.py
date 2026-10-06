"""Validate typed inputs and bind SQLite's actual slots without inventing slot numbers."""

import ctypes as c
import hashlib

from conformance.case_format import Json, cell_wire
from conformance.native_connection import Cell, Connection, Row

#: Captured helpers with reproduced result semantics; row scripts cannot carry source bindings.
TCL_SQL_HELPERS = frozenset({"eval", "eval-script", "onecolumn", "exists",
                             "aux:eval", "aux:eval-script", "aux:onecolumn", "aux:exists"})
#: Native output/profile formats that can retain complete typed slot evidence.
BINDING_NATIVE_VERSIONS = (3, 4)
#: Every source call carries these observed values and conditions before prefix minimization.
TCL_CALL_FIELDS = {"sql", "helper", "code", "results", "precision", "nullValue", "bindings", "objects"}


def decode_cell(value: Json) -> Cell:
    """Reject malformed native cell transport rather than coercing its payload."""
    if value == "null":
        return 5, None
    if not isinstance(value, dict) or len(value) != 1:
        raise ValueError("Invalid native cell")
    kind, payload = next(iter(value.items()))
    if not isinstance(payload, dict):
        raise ValueError("Invalid native cell payload")
    if kind == "integer" and type(payload.get("value")) is int and -(2**63) <= payload["value"] < 2**63:
        return 1, payload["value"]
    if kind == "real" and isinstance(payload.get("bits"), str) and payload["bits"].isdigit():
        bits = int(payload["bits"])
        if bits < 2**64:
            return 2, bits
    if kind in ("text", "blob") and isinstance(payload.get("bytes"), list):
        data = payload["bytes"]
        if all(type(byte) is int and 0 <= byte < 256 for byte in data):
            return (3 if kind == "text" else 4), bytes(data)
    raise ValueError("Invalid native cell payload")


def decode_rows(rows: list[Json]) -> list[Row]:
    """Restore typed metadata from the frozen JSON encoding."""
    return [tuple(decode_cell(cell) for cell in row) for row in rows]


def canonical_cell(value: Json) -> Cell:
    """New binding evidence uses the existing codec's exact shape, including NULL."""
    cell = decode_cell(value)
    if cell_wire(cell) != value:
        raise ValueError("Invalid canonical native binding cell")
    return cell


def parameter_names(connection: Connection, statement: c.c_void_p) -> list[str | None]:
    """SQLite numbers slots, including repeated names and gaps in numbered parameters."""
    library = connection.library
    return [value.decode() if value is not None else None for index in range(1,
        library.sqlite3_bind_parameter_count(statement) + 1)
        for value in [library.sqlite3_bind_parameter_name(statement, index)]]


def checked_binding(value: Json) -> tuple[list[str | None], Row]:
    """Reject incomplete vectors before unsupported model admission can hide them."""
    if not isinstance(value, dict) or set(value) != {"parameterNames", "parameters"}:
        raise ValueError("Invalid native binding metadata")
    names, values = value["parameterNames"], value["parameters"]
    if (not isinstance(names, list) or any(name is not None and
            (not isinstance(name, str) or len(name) < 2 or name[0] not in "?:@$" or "\x00" in name) for name in names)
            or len([name for name in names if name is not None]) != len({name for name in names if name is not None})
            or not isinstance(values, list) or len(names) != len(values)):
        raise ValueError("Invalid native binding slot names or count")
    return names, tuple(canonical_cell(cell) for cell in values)


def call_slots(call: dict[str, Json]) -> dict[str, Cell]:
    """Require complete observed Tcl names while leaving slot numbering to SQLite."""
    from conformance.upstream_bindings import named_slots
    values, objects = call.get("bindings"), call.get("objects")
    if (not isinstance(values, dict) or not isinstance(objects, dict)
            or set(values) != set(named_slots(call["sql"])) or set(objects) != set(values)):
        raise ValueError("Tcl parameter observation names differ from source SQL")
    if values and call["helper"].endswith("eval-script"):
        raise ValueError("Tcl row variable assignments can change parameter bindings")
    for name in values:
        variable = name[1:].removeprefix("::")
        if not variable or any(not (character.isalnum() or character == "_") for character in variable):
            raise ValueError("Unsupported Tcl scalar parameter variable form")
        if name.startswith("@") and any(other[1:] == name[1:] and not other.startswith("@") for other in values):
            raise ValueError("Mixed Tcl parameter conversion is unobservable")
    for value in objects.values():
        if (not isinstance(value, dict) or set(value) != {"type", "hasString"}
                or not isinstance(value["type"], str) or not value["type"]
                or type(value["hasString"]) is not bool):
            raise ValueError("Invalid Tcl parameter object evidence")
    return {name: canonical_cell(value) for name, value in values.items()}


def checked_call(value: Json) -> dict[str, Json]:
    """Source calls retain their observed types, display context and original expectations."""
    from conformance.upstream_result_values import TCL_MAX_PRECISION
    if (not isinstance(value, dict) or set(value) != TCL_CALL_FIELDS
            or not isinstance(value["sql"], str) or "\x00" in value["sql"]
            or not isinstance(value["helper"], str)
            or value["helper"] not in TCL_SQL_HELPERS
            or type(value["code"]) is not int or value["code"] < 0
            or not isinstance(value["results"], list)
            or any(not isinstance(item, str) for item in value["results"])
            or value["precision"] is not None and (type(value["precision"]) is not int
                or not 0 <= value["precision"] <= TCL_MAX_PRECISION)
            or value["nullValue"] is not None and not isinstance(value["nullValue"], str)):
        raise ValueError("Invalid retained Tcl SQL call")
    call_slots(value)
    return value


def statement_bindings(connection: Connection, statement: c.c_void_p, provided: Row,
                       expected: list[str | None] | None,
                       call: dict[str, Json] | None) -> tuple[list[str | None], Row]:
    """Check observed names and replay inputs against the prepared statement before stepping."""
    names = parameter_names(connection, statement) if statement.value else []
    if expected is not None and names != expected:
        raise ValueError("Native parameter slot names differ from recorded inputs")
    if call is not None:
        values = call_slots(call)
        if not statement.value and values:
            raise ValueError("Tcl parameter slots are unobservable after a prepare error")
        if any(name is None or name not in values for name in names):
            raise ValueError("Tcl parameter slot has no observed value")
        bound = tuple(values[name] for name in names)
        if provided and provided != bound:
            raise ValueError("Recorded parameters differ from the Tcl call bindings")
    else:
        bound = provided
    if len(names) != len(bound):
        raise ValueError("Expected one typed value per SQLite parameter slot")
    return names, bound


def check_source_results(record: dict[str, Json]) -> None:
    """Retained source expectations must still fit the current replayed setup and assertion calls."""
    if record.get("bindingRecordingKind") != "tcl":
        return
    from conformance.native_call_recording import source_setup
    from conformance.upstream_fidelity import check_results
    setup, assertion = source_setup(record), record["sourceCalls"]["assertion"]
    candidate: dict[str, Json] = {"commands": [call["sql"] for call in assertion]}
    for field, key, default in (("Codes", "code", 0), ("Results", "results", []),
                               ("Helpers", "helper", "eval"), ("Precisions", "precision", None),
                               ("NullValues", "nullValue", None)):
        candidate["prefix" + field] = [call[key] if call is not None else default for call in setup]
        candidate[field[0].lower() + field[1:]] = [call[key] for call in assertion]
    check_results(record, candidate)


def check_source_digest(record: dict[str, Json]) -> None:
    """A retained acquisition digest identifies the original call inputs even if outputs do not change."""
    from conformance.native_storage import serialized
    upstream = record.get("upstream")
    if isinstance(upstream, dict) and "tclCallsSha256" in upstream:
        if (record.get("bindingRecordingKind") != "tcl" or not isinstance(upstream["tclCallsSha256"], str)
                or hashlib.sha256(serialized(record["sourceCalls"])).hexdigest() != upstream["tclCallsSha256"]):
            raise ValueError("Retained Tcl source call digest differs")
