"""Bind source-family profiles and round-trip capture conditions before a repaired freeze."""

from conformance.case_format import Json
from conformance.execution_profile import ExecutionProfile, recorded_profile
from conformance.native_storage import serialized
from conformance.upstream_profiles import tcl_precision_policy
from conformance.upstream_result_values import TCL_MAX_PRECISION

PRECISION_POLICY = tcl_precision_policy()


def file_conditions(file: dict[str, Json], profile: ExecutionProfile, clock: int | None) -> None:
    """Validate recorded conditions without consulting today's source routing policy."""
    identity = file.get("executionProfile")
    precision = file.get("tclDisplayPrecision")
    if (not isinstance(identity, dict) or identity != {"name": profile.name, "version": profile.version}
            or type(identity.get("version")) is not int
            or "clockUnixMilliseconds" not in file or file["clockUnixMilliseconds"] != clock
            or clock is not None and type(file["clockUnixMilliseconds"]) is not int
            or not isinstance(precision, dict) or set(precision) != {"original", "established", "requested"}
            or any(type(value) is not int or value < 0 for value in precision.values())
            or precision["established"] != 0 or precision["requested"] != 0):
        raise ValueError("Acquisition source profile, clock or Tcl precision differs")


def result_precision(value: Json, *, accepted: bool, policy_version: int) -> None:
    """Keep v1's zero-only guarantee and v2's observed source precision in retained evidence."""
    if (not isinstance(value, dict) or set(value) != {"values", "successfulCalls"}
            or type(value["successfulCalls"]) is not int or value["successfulCalls"] < 0
            or not isinstance(value["values"], list)
            or any(item is not None and (type(item) is not int or item < 0) for item in value["values"])
            or value["values"] != sorted(set(value["values"]), key=lambda item: -1 if item is None else item)
            or bool(value["successfulCalls"]) != bool(value["values"])
            or len(value["values"]) > value["successfulCalls"]
            or policy_version not in (1, 2)
            or accepted and (None in value["values"] or any(item > TCL_MAX_PRECISION for item in value["values"])
                or policy_version == 1 and value["values"] != ([0] if value["successfulCalls"] else []))):
        raise ValueError("Acquisition result precision evidence differs")


def result_nullvalue(value: Json, precision: Json, *, accepted: bool) -> None:
    """Keep observed Tcl NULL display markers separate from unchanged native typed cells."""
    if (not isinstance(value, dict) or set(value) != {"values", "successfulCalls"}
            or type(value["successfulCalls"]) is not int or value["successfulCalls"] < 0
            or not isinstance(precision, dict) or value["successfulCalls"] != precision["successfulCalls"]
            or not isinstance(value["values"], list)
            or any(item is not None and not isinstance(item, str) for item in value["values"])
            or value["values"] != sorted(set(value["values"]), key=lambda item: (item is not None, item or ""))
            or bool(value["successfulCalls"]) != bool(value["values"])
            or len(value["values"]) > value["successfulCalls"]
            or accepted and None in value["values"]):
        raise ValueError("Acquisition NULL display evidence differs")


def record_conditions(record: dict[str, Json], profile: ExecutionProfile, precision: Json, clock: int | None,
                      nullvalue: Json) -> None:
    """Every accepted case retains its source profile, clock and observed Tcl display conditions."""
    if (recorded_profile(record) != profile
            or clock is not None and (record.get("setupClockUnixMilliseconds") != clock
                or any(event.get("clockUnixMilliseconds") != clock for event in record["trace"]))
            or type(record["upstream"].get("tclDisplayPrecision")) is not int
            or record["upstream"]["tclDisplayPrecision"] != 0
            or serialized(record["upstream"].get("tclResultPrecision")) != serialized(precision)
            or serialized(record["upstream"].get("tclNullvalueEvidence")) != serialized(nullvalue)):
        raise ValueError("Acquisition record profile, clock or Tcl display evidence differs")
