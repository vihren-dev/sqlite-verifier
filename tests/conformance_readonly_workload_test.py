"""Actual read-only native execution survives the generic directory and replay boundary."""

from dataclasses import replace
import json
from pathlib import Path
import subprocess
import sys

import pytest

from conformance.corpus import load, native_replay
from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, NativeError, library_path, load_library
from conformance.native_record import record_sql
from conformance.workload import bound_records, record

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3-3.53.4")]


def inputs(directory: Path) -> None:
    """Bind a neutral fixture, typed reads and an intentional final failed write."""
    directory.mkdir()
    connection = Connection(load_library(library_path("sqlite3-3.53.4"), "3.53.4"), directory / "measure.db")
    try:
        profile = measured_profile(connection, name="readonly-directory", format_version=2,
            trusted_schema=False, dqs_dml=False, dqs_ddl=False, access_mode="read-only")
    finally:
        connection.close()
    (directory / "profile.json").write_text(json.dumps(profile.to_wire()))
    (directory / "schema.sql").write_text("CREATE TABLE t(id PRIMARY KEY, label); INSERT INTO t VALUES(7,'fixture');")
    (directory / "read.sql").write_text("SELECT id,label FROM t WHERE id=?;")
    (directory / "write.sql").write_text("INSERT INTO t VALUES(8,'denied'); -- final denial\n")
    inventory = {"workloadFormatVersion": 1, "profile": "profile.json", "setup": ["schema.sql"],
        "cases": [{"name": "typed-read", "sql": "read.sql", "parameters": [[{"integer": {"value": 7}}]],
                   "features": ["select"]},
                  {"name": "write-denial", "sql": "write.sql", "parameters": [[]],
                   "features": ["readonly"]}]}
    (directory / "workload.json").write_text(json.dumps(inventory))


def command(arguments: list[str]) -> None:
    """Exercise the real directory CLI in a bounded child process."""
    subprocess.run([sys.executable, "-m", "conformance.workload", *arguments],
                   cwd=ROOT, check=True, capture_output=True, text=True, timeout=45)


def test_readonly_directory_freeze_load_and_fresh_replay(tmp_path: Path, runtime_root: Path) -> None:
    """Read-only setup is committed separately and denied writes remain scoped native evidence."""
    source, frozen = tmp_path / "input", tmp_path / "frozen"
    inputs(source)
    command(["record", str(source), "--output", str(frozen)])
    manifest, records = bound_records(source, frozen)
    assert manifest["nativeReplayPassed"] and manifest["recordedCases"] == 2
    assert load(frozen) == (manifest, records)
    assert records[0]["trace"][0]["rows"] == [[{"integer": {"value": 7}},
                                               {"text": {"bytes": list(b"fixture")}}]]
    error = records[1]["trace"][0]
    assert error["primaryCode"] == error["extendedCode"] == 8
    assert error["visible"] == error["persisted"] == records[1]["initial"]["visible"]
    assert not error["transactionOpen"]
    native_replay(records)
    output = tmp_path / "replay.json"
    command(["replay", str(source), "--corpus", str(frozen), "--runtime-root", str(runtime_root),
             "--output", str(output)])
    assert json.loads(output.read_text())["counts"] == {"MODEL_UNSUPPORTED": 2}
    from conformance.execution_profile import profile_from_wire
    profile = profile_from_wire(records[0]["profile"])
    with pytest.raises(ValueError, match="profile differs"):
        native_replay(records, profile=replace(profile, access_mode="read-write"))
    manifest_path = frozen / "manifest.json"
    original_manifest = manifest_path.read_bytes()
    altered = {**manifest, "executionProfiles": [replace(profile, trusted_schema=True).to_wire()]}
    manifest_path.write_text(json.dumps(altered))
    with pytest.raises(ValueError, match="profile differs from manifest"):
        load(frozen)
    manifest_path.write_bytes(original_manifest)
    (source / "write.sql").write_text("INSERT INTO t VALUES(8,'denied'); SELECT 99;")
    value = json.loads((source / "workload.json").read_text())
    value["cases"][1]["parameters"] = [[], []]
    (source / "workload.json").write_text(json.dumps(value))
    with pytest.raises(ValueError, match="unexecuted"):
        record(source, tmp_path / "incomplete")
    assert not (tmp_path / "incomplete").exists()


def test_readonly_reopen_and_environmental_error_boundary(tmp_path: Path,
                                                        monkeypatch: pytest.MonkeyPatch) -> None:
    """Initialization reopens retain settings; extended filesystem denials cannot become evidence."""
    from conformance.execution_profile import profile_from_wire
    source = tmp_path / "input"
    inputs(source)
    profile = profile_from_wire(json.loads((source / "profile.json").read_text()))
    setup = ["CREATE TABLE t(id);", {"reopen": True}, {"dbConfig": [1013, 0]},
             {"dbConfig": [1014, 0]}, {"dbConfig": [1017, 0]}, "INSERT INTO t VALUES(1);"]
    evidence = record_sql(setup, "BEGIN; SELECT id FROM t; COMMIT; INSERT INTO t VALUES(2);",
        name="reopen", outputs=True, profile=profile)
    assert evidence["setupOutcomes"] == [0] * 6
    assert evidence["trace"][1]["rows"] == [[{"integer": {"value": 1}}]]
    assert evidence["trace"][0]["transactionOpen"] and not evidence["trace"][2]["transactionOpen"]
    assert evidence["trace"][-1]["extendedCode"] == 8
    native_replay([evidence])
    original = Connection.check
    def environmental(connection: Connection, code: int) -> None:
        """Inject the recovery-specific extended failure at the shared native error boundary."""
        if code & 255 == 8:
            raise NativeError(264, "recovery failure")
        original(connection, code)
    monkeypatch.setattr(Connection, "check", environmental)
    with pytest.raises(NativeError) as denied:
        record_sql("CREATE TABLE t(id);", "INSERT INTO t VALUES(2);", name="environment",
                   outputs=True, profile=profile)
    assert denied.value.code == 264
