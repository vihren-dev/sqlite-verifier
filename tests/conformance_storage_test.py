"""Shared native storage preserves evidence and enforces acquisition byte limits."""

from copy import deepcopy
from dataclasses import replace
import gzip
import hashlib
import json
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_record import record_sql
from conformance.native_storage import CASE_BYTE_LIMIT, CaseSizeLimit, expanded_record, serialized, shared_record
from conformance.refresh_corpus import refresh

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def write_corpus(directory: Path, records: list[dict[str, Json]],
                 profiles: list[dict[str, Json]] | None = None) -> None:
    """Bind test transport to its real bytes so storage checks cannot hide behind digest errors."""
    directory.mkdir(exist_ok=True)
    payload = b"".join(serialized(record) + b"\n" for record in records)
    manifest = {"corpusVersion": 1, "recordedCases": len(records),
                "casesSha256": hashlib.sha256(payload).hexdigest()}
    if profiles is not None:
        manifest["executionProfiles"] = profiles
    (directory / "cases.jsonl.gz").write_bytes(gzip.compress(payload, mtime=0))
    (directory / "manifest.json").write_bytes(serialized(manifest))


def clock_profile(tmp_path: Path) -> dict[str, Json]:
    """Measure the actual pinned engine before constructing clock-dependent cases."""
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        return measured_profile(connection, name="storage-clock", foreign_keys=True,
            transaction_mode="immediate", clock="unix-milliseconds-v1").to_wire()
    finally:
        connection.close()


@pytest.mark.parametrize("version", [1, 2, 3, 4])
def test_native_storage_round_trip(tmp_path: Path, version: int) -> None:
    """Every native acquisition version survives shared and legacy load followed by fresh replay."""
    from conformance.execution_profile import profile_from_wire
    profile = profile_from_wire(clock_profile(tmp_path)) if version == 4 else None
    setup = "CREATE TABLE t(v BLOB); INSERT INTO t VALUES(1);"
    if profile is not None:
        setup = ("CREATE TABLE t(v BLOB,stamp DEFAULT(unixepoch())); CREATE TABLE audit(stamp);"
                 "CREATE TRIGGER log AFTER INSERT ON t BEGIN INSERT INTO audit VALUES(unixepoch()); END;"
                 "INSERT INTO t(v) VALUES(1);")
    commands = [{"reopen": True}, setup] if version == 2 else setup
    sql = ("BEGIN IMMEDIATE;" if version == 4 else "BEGIN;") + (
        "INSERT INTO t(v) VALUES(?) RETURNING v; SELECT v FROM t ORDER BY v LIMIT ?; ROLLBACK;"
        if version >= 3 else "INSERT INTO t VALUES(X'00ff'); SELECT v FROM t; ROLLBACK;")
    clocks = [1700000000000 + index * 1000 for index in range(4)]
    record = record_sql(commands, sql, name=f"storage-v{version}", outputs=version >= 3,
        parameters=[(), ((4, b"\x00\xff"),), ((1, 1),), ()] if version >= 3 else None,
        profile=profile, setup_clock=1699999999000 if profile else None,
        clock_values=clocks if profile else None)
    assert record["nativeVersion"] == version
    assert record["trace"][1]["visible"] != record["trace"][1]["persisted"]
    stored = shared_record(record)
    snapshots = {serialized(event[field]) for event in [record["initial"], *record["trace"]]
                 for field in ("visible", "persisted")}
    assert len(stored["snapshots"]) == len(snapshots)
    if version >= 3:
        assert record["trace"][1]["parameters"] == [{"blob": {"bytes": [0, 255]}}]
        assert record["trace"][2]["groups"][0]["count"] == 1
    if profile is not None:
        assert record["profile"] == profile.to_wire()
        assert [event["clockUnixMilliseconds"] for event in record["trace"]] == clocks
    for label, value in (("shared", stored), ("legacy", record)):
        directory = tmp_path / label
        write_corpus(directory, [value], [profile.to_wire()] if profile else None)
        loaded = load(directory)[1]
        assert loaded == [record]
        native_replay(loaded, profile=profile)
    restored = expanded_record(stored)
    restored["initial"]["visible"]["tables"][0]["rows"].clear()
    assert restored["initial"]["persisted"] == record["initial"]["persisted"]
    assert expanded_record(stored) == record


def test_utf8_exact_size_boundary() -> None:
    """The exact byte limit passes; one more byte fails even with multibyte metadata."""
    record = record_sql("CREATE TABLE t(v BLOB); INSERT INTO t VALUES(1);", "SELECT v FROM t;", name="é")
    record["padding"] = "a" * (CASE_BYTE_LIMIT - len(serialized({**record, "padding": ""})))
    assert len(serialized(record)) == CASE_BYTE_LIMIT
    assert len(serialized(shared_record(record))) <= CASE_BYTE_LIMIT
    record["padding"] += "a"
    with pytest.raises(CaseSizeLimit, match="case size limit") as failure:
        shared_record(record)
    assert failure.value.byte_count == CASE_BYTE_LIMIT + 1


def test_logically_oversized_case_cannot_hide_behind_sharing() -> None:
    """Repeated large snapshots remain an exclusion even when the stored pool is small."""
    record = record_sql("CREATE TABLE t(v BLOB); INSERT INTO t VALUES(zeroblob(20000));",
                        "SELECT count(*) FROM t;" * 12, name="oversized")
    assert len(serialized(record)) > CASE_BYTE_LIMIT
    assert len(serialized(shared_record(record, byte_limit=None))) < CASE_BYTE_LIMIT
    with pytest.raises(CaseSizeLimit):
        shared_record(record)


@pytest.mark.parametrize("damage", ["content", "missing", "reference", "version", "bool-version", "unused", "pool"])
def test_load_refuses_corrupt_shared_evidence(tmp_path: Path, damage: str) -> None:
    """Rebinding the outer corpus digest cannot conceal corrupt snapshot transport."""
    stored = shared_record(record_sql("CREATE TABLE t(v BLOB);", "SELECT v FROM t;", name="corruption"))
    broken = deepcopy(stored)
    digest = broken["initial"]["visible"]["snapshot"]
    if damage == "content":
        broken["snapshots"][digest]["tables"].clear()
    elif damage == "missing":
        del broken["snapshots"][digest]
    elif damage == "reference":
        broken["initial"]["visible"] = {"digest": digest}
    elif damage in {"version", "bool-version"}:
        broken["snapshotStorageVersion"] = 2 if damage == "version" else True
    elif damage == "unused":
        extra = {"schema": [], "tables": []}
        broken["snapshots"][hashlib.sha256(serialized(extra)).hexdigest()] = extra
    else:
        broken["snapshots"] = []
    write_corpus(tmp_path, [broken])
    with pytest.raises(ValueError, match="snapshot"):
        load(tmp_path)


def test_repeat_refresh_preserves_shared_parents_and_profiles(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Repeated refreshes retain shared parent evidence and all measured profile declarations."""
    from conformance.execution_profile import profile_from_wire
    first = profile_from_wire(clock_profile(tmp_path))
    second = replace(first, name="storage-clock-second")
    record = record_sql("", "SELECT unixepoch('now');", name="first", outputs=True,
                        profile=first, setup_clock=1700000000000, clock_values=1700000001000)
    addition = record_sql("", "SELECT unixepoch('now');", name="second", outputs=True,
                          profile=second, setup_clock=1700000002000, clock_values=1700000003000)
    base, capture = tmp_path / "base", tmp_path / "capture"
    write_corpus(base, [record], [first.to_wire()])
    write_corpus(capture, [shared_record(addition)], [second.to_wire()])
    inventory = tmp_path / "requirements.json"
    inventory.write_text('{"requirements":[]}')
    monkeypatch.setattr("conformance.refresh_corpus.authored_records", lambda: [])
    output, repeated = tmp_path / "output", tmp_path / "repeated"
    refresh(base, capture, inventory, output)
    refresh(output, capture, inventory, repeated)
    manifest, records = load(repeated)
    assert records == [record, addition]
    assert manifest["executionProfiles"] == [first.to_wire(), second.to_wire()]
    stored = [json.loads(line) for line in gzip.decompress((repeated / "cases.jsonl.gz").read_bytes()).splitlines()]
    assert all(item["snapshotStorageVersion"] == 1 for item in stored)
    native_replay(records)
