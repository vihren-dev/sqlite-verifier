"""Fresh native replay keeps observed call inputs and rejects corrupt slot evidence."""

from copy import deepcopy
import gzip
import hashlib
from pathlib import Path

import pytest

from conformance.case_format import Json, cell_wire
from conformance.corpus import load, native_replay
from conformance.corpus_shards import write
from conformance.execution_profile import ExecutionProfile, measured_profile
from conformance.native_connection import Cell, Connection, library_path, load_library
from conformance.native_record import record_sql
from conformance.native_replay import prepare
from conformance.native_storage import serialized
from conformance.upstream_fidelity import minimize_prefix
from conformance.upstream_helpers import join_commands

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def call(sql: str, results: list[str], bindings: dict[str, Cell] | None = None) -> dict[str, Json]:
    """Supply retained scalar observations without guessing SQLite parameter numbering."""
    values = bindings or {}
    return {"sql": sql, "helper": "eval", "code": 0, "results": results, "precision": 0,
        "nullValue": "", "bindings": {name: cell_wire(value) for name, value in values.items()},
        "objects": {name: {"type": "int", "hasString": False} for name in values}}


@pytest.fixture
def profile(tmp_path: Path) -> ExecutionProfile:
    """Measure the actual pinned engine for loader and pre-admission corruption checks."""
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        return measured_profile(connection, name="binding-regression")
    finally:
        connection.close()


def source_record(profile: ExecutionProfile | None = None) -> dict[str, Json]:
    """An unrelated prefix precedes a value-dependent setup and a changed repeated parameter."""
    setup = [call("SELECT 13", ["13"]), call("CREATE TABLE t(v)", []),
             call("INSERT INTO t VALUES($v)", [], {"$v": (1, 7)})]
    assertion = [call("SELECT v FROM t", ["7"]), call("SELECT $v,$v", ["9", "9"], {"$v": (1, 9)})]
    return record_sql([item["sql"] for item in setup], join_commands([item["sql"] for item in assertion]),
        name="source-bindings", outputs=True, profile=profile,
        tcl_calls={"version": 1, "setup": setup, "assertion": assertion})


def test_named_call_replay_and_prefix_minimization() -> None:
    """Repeated names share one slot, call values change, and minimized inputs stay paired."""
    record = source_record()
    original = deepcopy(record["sourceCalls"])
    assert record["nativeVersion"] == 3 and record["bindingRecordingVersion"] == 1
    assert record["setupBindings"][2] == [{"parameterNames": ["$v"], "parameters": [{"integer": {"value": 7}}]}]
    assert record["trace"][1]["parameterNames"] == ["$v"]
    assert record["trace"][1]["parameters"] == [{"integer": {"value": 9}}]
    native_replay([record])
    minimized = minimize_prefix(record)
    assert minimized["setupCommands"] == ["CREATE TABLE t(v)", "INSERT INTO t VALUES($v)"]
    assert minimized["setupCallIndices"] == [1, 2]
    assert minimized["setupHelpers"] == ["eval", "eval"]
    assert minimized["sourceCalls"] == original
    assert minimized["sourceSetupCommands"] == [item["sql"] for item in original["setup"]]
    native_replay([minimized])


def test_explicit_setup_preserves_all_storage_classes() -> None:
    """The flexible primitive binds bytes, exact REAL bits and directly supplied NULL values."""
    cells = ((1, -(2**63)), (2, 1 << 63), (3, b"a\x00b"), (4, b"\x00\xff"), (5, None))
    record = record_sql(["CREATE TABLE t(a,b,c,d,e)", "INSERT INTO t VALUES(?,?,?,?,?)"],
        "SELECT * FROM t", name="explicit-setup", outputs=True,
        setup_parameters=[[()], [cells]])
    assert record["bindingRecordingKind"] == "explicit"
    assert record["setupBindings"][1][0]["parameterNames"] == [None] * 5
    assert record["trace"][0]["rows"] == [[cell_wire(cell) for cell in cells]]
    native_replay([record])


def test_equal_values_cannot_hide_changed_slot_names() -> None:
    """Changing only names fails against SQLite even when both bound values and outputs agree."""
    record = record_sql("", "SELECT :left,:right", name="equal-values", outputs=True,
        parameters=[((1, 7), (1, 7))], setup_parameters=[[]])
    record["trace"][0]["parameterNames"] = [":right", ":left"]
    with pytest.raises(ValueError, match="slot names differ"):
        native_replay([record])


def test_explicit_numbered_gaps_and_error_input_completeness() -> None:
    """The primitive preserves SQLite gaps while errors cannot hide missing or surplus vectors."""
    record = record_sql([], "SELECT ?3,:same,:same", name="numbered-slots", outputs=True,
        setup_parameters=[], parameters=[((1, 7), (1, 8), (1, 9), (1, 10))])
    assert record["trace"][0]["parameterNames"] == [None, None, "?3", ":same"]
    assert record["trace"][0]["rows"] == [[{"integer": {"value": value}} for value in (9, 10, 10)]]
    native_replay([record])
    for parameters in ([], [(), ()]):
        with pytest.raises(ValueError, match="metadata.*statement"):
            record_sql([], "SELECT * FROM absent", name="error-inputs", outputs=True,
                       setup_parameters=[], parameters=parameters)


def test_original_control_references_survive_minimization() -> None:
    """Removing a redundant reopen preserves its original operation and null source-call entry."""
    commands = ["CREATE TABLE t(v)", {"reopen": True}, "INSERT INTO t VALUES($v)"]
    calls = {"version": 1, "setup": [call(commands[0], []), None, call(commands[2], [], {"$v": (1, 7)})],
             "assertion": [call("SELECT v FROM t", ["7"])]}
    record = record_sql(commands, "SELECT v FROM t", name="control-bindings", outputs=True, tcl_calls=calls)
    minimized = minimize_prefix(record)
    assert minimized["setupCallIndices"] == [0, 2]
    assert minimized["sourceSetupCommands"] == commands and minimized["sourceCalls"] == calls
    native_replay([minimized])


@pytest.mark.parametrize("damage", ["version", "missing", "duplicate", "setup-count", "source-name", "source-value", "expected"])
def test_malformed_inputs_fail_before_profile_unsupported(profile: ExecutionProfile, damage: str) -> None:
    """A valid explicit profile cannot conceal malformed or inconsistent retained binding inputs."""
    record = source_record(profile)
    assert prepare(record, Path("/unused-parser"))[1]["verdict"] == "MODEL_UNSUPPORTED"
    if damage == "version":
        record["bindingRecordingVersion"] = True
    elif damage == "missing":
        del record["trace"][1]["parameterNames"]
    elif damage == "duplicate":
        record["trace"][1]["parameterNames"].append("$v")
        record["trace"][1]["parameters"].append({"integer": {"value": 9}})
    elif damage == "setup-count":
        record["setupBindings"].pop()
    elif damage == "source-name":
        record["trace"][1]["parameterNames"] = ["$other"]
    elif damage == "source-value":
        record["setupBindings"][2][0]["parameters"][0] = {"integer": {"value": 8}}
    else:
        record["sourceCalls"]["assertion"][0]["results"] = ["8"]
    assert prepare(record, Path("/unused-parser"))[1]["verdict"] == "HARNESS_ERROR"
    with pytest.raises(ValueError):
        native_replay([record])


def test_coherent_setup_value_corruption_fails_fresh_execution() -> None:
    """Changing both copies of a setup input cannot alter its frozen result or native state."""
    record = source_record()
    record["sourceCalls"]["setup"][2]["bindings"]["$v"] = {"integer": {"value": 8}}
    record["setupBindings"][2][0]["parameters"][0] = {"integer": {"value": 8}}
    with pytest.raises(ValueError, match="differ|changed"):
        native_replay([record])


def test_source_digest_binds_values_that_do_not_change_outputs() -> None:
    """An unchanged result cannot conceal changed acquired input identities."""
    calls = {"version": 1, "setup": [], "assertion": [call("SELECT 0*$v", ["0"], {"$v": (1, 7)})]}
    record = record_sql([], "SELECT 0*$v", name="unchanged-output", outputs=True, tcl_calls=calls)
    record["upstream"] = {"tclCallsSha256": hashlib.sha256(serialized(calls)).hexdigest()}
    record["sourceCalls"]["assertion"][0]["bindings"]["$v"] = {"integer": {"value": 8}}
    record["trace"][0]["parameters"][0] = {"integer": {"value": 8}}
    with pytest.raises(ValueError, match="source call digest differs"):
        native_replay([record])


@pytest.mark.parametrize("sql,bindings", [("SELECT ?", {}),
    ("SELECT $v FROM absent", {"$v": (1, 7)}), ("SELECT $v", {}),
    ("SELECT $v(1)", {"$v(1)": (1, 7)})])
def test_unobserved_slots_are_refused(sql: str, bindings: dict[str, Cell]) -> None:
    """Anonymous, failed-prepare, missing and unsupported source slots never become guessed NULLs."""
    observation = call(sql, [], bindings)
    with pytest.raises(ValueError):
        record_sql([], sql, name="refused-binding", outputs=True,
                   tcl_calls={"version": 1, "setup": [], "assertion": [observation]})


def test_rebound_shard_cannot_hide_incomplete_metadata(tmp_path: Path, profile: ExecutionProfile) -> None:
    """Even freshly recomputed corpus digests cannot bypass the logical binding validator."""
    import json
    record = source_record(profile)
    record["part"] = "boundary-interaction"
    directory = tmp_path / "corpus"
    manifest = write(directory, [("authored", record["part"], [record])])
    shard = manifest["shards"][0]
    path = directory / shard["path"]
    stored = json.loads(gzip.decompress(path.read_bytes()))
    del stored["trace"][1]["parameterNames"]
    payload = serialized(stored) + b"\n"
    path.write_bytes(gzip.compress(payload, mtime=0))
    manifest["casesSha256"] = shard["casesSha256"] = hashlib.sha256(payload).hexdigest()
    (directory / "manifest.json").write_bytes(serialized(manifest))
    with pytest.raises(ValueError, match="binding"):
        load(directory)
