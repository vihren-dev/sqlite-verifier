"""Validate an external SQL inventory and bind every supplied file before recording."""

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json, cell_wire
from conformance.corpus_shards import source_path
from conformance.execution_profile import ExecutionProfile, profile_from_wire
from conformance.native_connection import Row
from conformance.native_replay import decode_cell
from conformance.upstream_helpers import join_commands


@dataclass(frozen=True)
class WorkloadCase:
    """One independently initialized SQL sequence with explicit parameter occurrences."""

    name: str
    setup: str
    sql: str
    parameters: list[Row]
    features: list[str]
    requirements: list[str]
    clocks: list[int] | None


@dataclass(frozen=True)
class WorkloadInputs:
    """Keep measured profile and source identities beside the validated inventory."""

    profile: ExecutionProfile
    cases: list[WorkloadCase]
    sources: dict[str, str]
    setup_clock: int | None


def strings(value: Json, label: str) -> list[str]:
    """Reject scalar coercion, empty names and duplicate inventory tags or file references."""
    if (not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value)
            or len(set(value)) != len(value)):
        raise ValueError(f"Invalid workload {label}")
    return value


def load_inputs(directory: Path) -> WorkloadInputs:
    """Require all SQL files to occur in the inventory; repeated fixtures may share a file."""
    directory = directory.resolve(strict=True)
    sources: dict[str, str] = {}
    sql_files: set[Path] = set()

    def read(relative: Json, *, sql: bool = False) -> str:
        """Hash exactly the bytes decoded for profile or SQL execution."""
        path = source_path(directory, relative)
        payload = path.read_bytes()
        sources[relative] = hashlib.sha256(payload).hexdigest()
        if sql:
            if path.suffix != ".sql":
                raise ValueError("Workload SQL reference must name a .sql file")
            sql_files.add(path.resolve())
        return payload.decode("utf-8")

    inventory = json.loads(read("workload.json"))
    required = {"workloadFormatVersion", "profile", "setup", "cases"}
    if (not isinstance(inventory, dict) or not required <= set(inventory)
            or set(inventory) - required - {"setupClockUnixMilliseconds"}
            or type(inventory["workloadFormatVersion"]) is not int or inventory["workloadFormatVersion"] != 1
            or not isinstance(inventory["cases"], list) or not inventory["cases"]):
        raise ValueError("Invalid workload inventory format")
    profile = profile_from_wire(json.loads(read(inventory["profile"])))
    setup = [read(name, sql=True) for name in strings(inventory["setup"], "setup files")]
    controlled = profile.clock == "unix-milliseconds-v1"
    setup_clock = inventory.get("setupClockUnixMilliseconds")
    if controlled != (type(setup_clock) is int) or not controlled and "setupClockUnixMilliseconds" in inventory:
        raise ValueError("Workload setup clock differs from execution profile")
    cases: list[WorkloadCase] = []
    names: set[str] = set()
    for entry in inventory["cases"]:
        fields = {"name", "sql", "parameters", "features"}
        if (not isinstance(entry, dict) or not fields <= set(entry)
                or set(entry) - fields - {"setup", "requirements", "clockUnixMilliseconds"}
                or not isinstance(entry["name"], str) or not entry["name"] or entry["name"] in names
                or not isinstance(entry["parameters"], list)):
            raise ValueError("Invalid or duplicate workload case")
        names.add(entry["name"])
        parameters: list[Row] = []
        for row in entry["parameters"]:
            if not isinstance(row, list):
                raise ValueError("Invalid workload parameter row")
            decoded = tuple(decode_cell(cell) for cell in row)
            if [cell_wire(cell) for cell in decoded] != row:
                raise ValueError("Invalid workload parameter encoding")
            parameters.append(decoded)
        clocks = entry.get("clockUnixMilliseconds")
        if (controlled and (not isinstance(clocks, list) or any(type(clock) is not int for clock in clocks))
                or not controlled and "clockUnixMilliseconds" in entry):
            raise ValueError("Workload statement clocks differ from execution profile")
        fixture = [read(name, sql=True) for name in strings(entry.get("setup", []), "case setup files")]
        cases.append(WorkloadCase(entry["name"], join_commands([*setup, *fixture]),
            read(entry["sql"], sql=True), parameters, strings(entry["features"], "features"),
            strings(entry.get("requirements", []), "requirements"), clocks))
    actual_sql = {path.resolve() for path in directory.rglob("*.sql") if path.is_file()}
    if actual_sql != sql_files:
        raise ValueError("Workload inventory does not account for every SQL file")
    return WorkloadInputs(profile, cases, sources, setup_clock)
