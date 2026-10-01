"""Profiles establish behavioral settings and refuse altered engine identities."""

from dataclasses import replace
from pathlib import Path
import time
import gzip
import hashlib
import json

import pytest

from conformance.execution_profile import measured_profile, profile_from_wire
from conformance.native_connection import Connection, library_path, load_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_profile_engine_settings_and_foreign_keys(tmp_path: Path) -> None:
    """Native readback and cascading behavior agree; false engine claims are refused."""
    connection = Connection(load_library(library_path()), tmp_path / "profile.db")
    try:
        profile = measured_profile(connection, name="synthetic-fk", foreign_keys=True,
            recursive_triggers=True, transaction_mode="immediate", clock="unix-milliseconds-v1")
        profile.establish(connection)
        assert profile_from_wire(profile.to_wire()) == profile
        for altered_wire in ({**profile.to_wire(), "version": True},
                             {**profile.to_wire(), "compileOptions": "WRONG"},
                             {**profile.to_wire(), "ignoredSettings": [["cache_size"]]},
                             {**profile.to_wire(), "unknown": 1}):
            with pytest.raises(ValueError, match="execution profile"):
                profile_from_wire(altered_wire)
        connection.execute_script("CREATE TABLE p(id PRIMARY KEY);"
            "CREATE TABLE child(id REFERENCES p(id) ON DELETE CASCADE);"
            "INSERT INTO p VALUES(1); INSERT INTO child VALUES(1); BEGIN IMMEDIATE;")
        with pytest.raises(ValueError, match="outside a transaction"):
            profile.establish(connection)
        connection.query("DELETE FROM p;")
        assert connection.query("SELECT * FROM child;") == []
        connection.execute_script("COMMIT;")
        for altered in (replace(profile, source_id="wrong"),
                        replace(profile, engine_version="wrong"),
                        replace(profile, compile_options=("WRONG",))):
            with pytest.raises(ValueError, match="engine identity differs"):
                altered.establish(connection)
        for arguments in ({"clock": "ambient"}, {"transaction_mode": "unknown"}, {"version": True}):
            with pytest.raises(ValueError, match="unsupported execution profile"):
                replace(profile, **arguments)
    finally:
        connection.close()


def test_recorded_profile_clock_and_fresh_replay(tmp_path: Path, runtime_root: Path) -> None:
    """Replay later wall time using stored clocks, preserving defaults/triggers and probes."""
    from conformance.corpus import load, native_replay
    from conformance.native_record import record_sql
    from conformance.native_replay import prepare
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="synthetic-clock", foreign_keys=True,
            transaction_mode="immediate", clock="unix-milliseconds-v1")
    finally:
        connection.close()
    setup = ("CREATE TABLE t(stamp DEFAULT(unixepoch())); CREATE TABLE audit(stamp);"
        "CREATE TRIGGER log AFTER INSERT ON t BEGIN INSERT INTO audit VALUES(unixepoch()); END;")
    sql = ("BEGIN IMMEDIATE; INSERT INTO t DEFAULT VALUES RETURNING stamp;"
        "SELECT stamp,unixepoch('now') AS now FROM audit ORDER BY now LIMIT 1; COMMIT;")
    clocks = [1700000000000, 1700000001000, 1700000002000, 1700000003000]
    wall_before = time.time_ns()
    record = record_sql(setup, sql, name="clock-replay", outputs=True, profile=profile,
                        setup_clock=1699999999000, clock_values=clocks)
    assert record["nativeVersion"] == 4
    assert [event["clockUnixMilliseconds"] for event in record["trace"]] == clocks
    assert record["trace"][1]["rows"] == [[{"integer": {"value": 1700000001}}]]
    assert record["trace"][2]["rows"] == [[{"integer": {"value": 1700000001}},
                                          {"integer": {"value": 1700000002}}]]
    assert record["trace"][2]["groups"][0]["count"] == 1
    time.sleep(0.01)
    assert time.time_ns() > wall_before
    native_replay([record], profile=profile)
    payload = (json.dumps(record) + "\n").encode()
    manifest = {"corpusVersion": 4, "recordedCases": 1,
                "casesSha256": hashlib.sha256(payload).hexdigest(),
                "executionProfiles": [profile.to_wire()]}
    (tmp_path / "cases.jsonl.gz").write_bytes(gzip.compress(payload))
    (tmp_path / "manifest.json").write_text(json.dumps(manifest))
    assert load(tmp_path) == (manifest, [record])
    for declarations in ([], [replace(profile, foreign_keys=False).to_wire()],
                         [profile.to_wire(), profile.to_wire()]):
        (tmp_path / "manifest.json").write_text(json.dumps({**manifest, "executionProfiles": declarations}))
        with pytest.raises(ValueError, match="profile"):
            load(tmp_path)
    assert prepare(record, runtime_root / "build/sqlite-parser")[1]["verdict"] == "MODEL_UNSUPPORTED"
    malformed = {**record, "setupClockUnixMilliseconds": True}
    assert prepare(malformed, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"
    with pytest.raises(ValueError, match="profile differs"):
        native_replay([record], profile=replace(profile, foreign_keys=False))
    with pytest.raises(ValueError, match="one clock value"):
        record_sql(setup, sql, name="missing-clock", outputs=True, profile=profile,
                   setup_clock=1699999999000, clock_values=[])
    for sql, reason in (("BEGIN;", "transaction mode differs"),
                        ("PRAGMA foreign_keys=OFF;", "established execution profile")):
        with pytest.raises(ValueError, match=reason):
            record_sql(setup, sql, name="changed-profile", outputs=True, profile=profile,
                       setup_clock=1699999999000, clock_values=[1700000000000])
