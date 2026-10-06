"""Catalog convenience profiles over the flexible explicit-profile acquisition primitive."""

from dataclasses import replace
from fnmatch import fnmatchcase
from io import StringIO
import os
from pathlib import Path
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.execution_profile import ExecutionProfile, measured_profile
from conformance.native_connection import Connection, library_path, load_library

CLOCK_UNIX_MILLISECONDS = 1700000000000
FOREIGN_KEY_PATTERNS = ("fkey*.test", "e_fkey.test", "e_changes.test", "e_delete.test")
CLOCK_PATTERNS = ("date*.test", "e_expr.test", "expr*.test", "func*.test", "cast.test")
PROFILE_NAMES = {
    (False, False): "upstream-default-deferred", (True, False): "upstream-fkey-deferred",
    (False, True): "upstream-clock-deferred", (True, True): "upstream-fkey-clock-deferred",
}


def source_profile_policy() -> dict[str, Json]:
    """Declare deterministic source routing; source SQL never changes this selection policy."""
    return {"version": 1, "foreignKeyOnPatterns": list(FOREIGN_KEY_PATTERNS),
            "controlledClockPatterns": list(CLOCK_PATTERNS),
            "clockUnixMilliseconds": CLOCK_UNIX_MILLISECONDS, "transactionMode": "deferred",
            "profiles": [{"name": name, "version": 1, "foreignKeys": foreign_keys,
                          "clock": "unix-milliseconds-v1" if controlled else "excluded"}
                         for (foreign_keys, controlled), name in PROFILE_NAMES.items()]}


def profile_name_for_source(filename: str) -> str:
    """Choose a declared source-family identity without querying or assuming engine options."""
    foreign_keys = any(fnmatchcase(filename, pattern) for pattern in FOREIGN_KEY_PATTERNS)
    controlled = any(fnmatchcase(filename, pattern) for pattern in CLOCK_PATTERNS)
    return PROFILE_NAMES[foreign_keys, controlled]


def catalog_profiles() -> dict[str, ExecutionProfile]:
    """Measure the actual pinned native build once, retaining its complete engine identity."""
    with TemporaryDirectory(prefix="upstream-profiles-") as directory:
        connection = Connection(load_library(library_path()), Path(directory) / "measure.db")
        try:
            base = measured_profile(connection, name=PROFILE_NAMES[False, False])
        finally:
            connection.close()
    return {name: replace(base, name=name, foreign_keys=foreign_keys,
                          clock="unix-milliseconds-v1" if controlled else "excluded")
            for (foreign_keys, controlled), name in PROFILE_NAMES.items()}


def profile_for_source(filename: str, profiles: dict[str, ExecutionProfile]) -> tuple[ExecutionProfile, int | None]:
    """Return the full measured profile and explicit clock input required by a catalog file."""
    profile = profiles[profile_name_for_source(filename)]
    return profile, CLOCK_UNIX_MILLISECONDS if profile.clock == "unix-milliseconds-v1" else None


def tcl_precision_policy() -> dict[str, Json]:
    """Start at precision zero, then accept observed source precision only with exact REAL bits."""
    return {"version": 2, "requested": 0, "establishAfter": "tester.tcl"}


def precision_observation(events: str) -> dict[str, Json] | None:
    """Retain the original and established Tcl precision measured by the real source hook."""
    result: list[dict[str, Json]] = []
    for line in StringIO(events):
        if not line.startswith(b"precision-policy".hex() + "\t"):
            continue
        values = [bytes.fromhex(field).decode() for field in line.rstrip("\r\n").split("\t")[1:]]
        if len(values) != 3:
            raise ValueError("Invalid Tcl display precision observation")
        result.append({name: int(value) if value else None for name, value in
                       zip(("original", "established", "requested"), values, strict=True)})
    return result[0] if len(result) == 1 else None


def capture_conditions(profile: ExecutionProfile | None, clock: int | None,
                       tcl_precision: int | None = None) -> dict[str, str]:
    """Establish only representable Tcl settings; changing source clocks remain excluded."""
    if profile is not None and profile.engine_version != "3.51.0":
        raise ValueError("Upstream capture requires the pinned 3.51.0 testfixture")
    controlled = profile is not None and profile.clock == "unix-milliseconds-v1"
    if controlled != (clock is not None) or clock is not None and (
            type(clock) is not int or clock % 1000 or not 0 < clock // 1000 <= 2147483647):
        raise ValueError("Tcl capture clock must be nonzero whole seconds in its signed 32-bit range")
    conditions = ({"CONFORMANCE_FOREIGN_KEYS": str(int(profile.foreign_keys)),
                   "CONFORMANCE_RECURSIVE_TRIGGERS": str(int(profile.recursive_triggers)), "TZ": "UTC0"}
                  if profile is not None else {})
    if controlled:
        conditions["CONFORMANCE_CLOCK_SECONDS"] = str(clock // 1000)
    if tcl_precision is not None:
        if type(tcl_precision) is not int or tcl_precision != 0:
            raise ValueError("Declared Tcl display precision must be round-trip precision zero")
        conditions["CONFORMANCE_TCL_PRECISION"] = str(tcl_precision)
    return conditions


def capture_environment(conditions: dict[str, str]) -> dict[str, str]:
    """Prevent ambient recorder flags from supplying unrequested Tcl execution conditions."""
    controlled = {"CONFORMANCE_FOREIGN_KEYS", "CONFORMANCE_RECURSIVE_TRIGGERS",
                  "CONFORMANCE_CLOCK_SECONDS", "CONFORMANCE_TCL_PRECISION"}
    return {**{name: value for name, value in os.environ.items() if name not in controlled}, **conditions}
