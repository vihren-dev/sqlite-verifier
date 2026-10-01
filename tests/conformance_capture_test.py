"""Real pinned Tcl capture establishes profiles before cross-engine fidelity checks."""

import gzip
import json
import os
from pathlib import Path
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, library_path, load_library
from conformance.upstream_pilot import pilot

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_real_profile_capture_and_clock_change_refusal(tmp_path: Path) -> None:
    """Default/trigger clocks and cascading deletes replay; an upstream clock change is excluded."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="capture-clock", foreign_keys=True,
            transaction_mode="immediate", clock="unix-milliseconds-v1")
    finally:
        connection.close()
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    source = Path(__file__).with_name("upstream_profile_calls.test")
    shutil.copyfile(source, upstream / "test/profile.test")
    output = tmp_path / "capture"
    report = pilot(Path(fixture), upstream, output, 10, ("profile.test",),
        profile=profile, clock=1700000000000)
    assert report["recordedCases"] == 2, report["files"]
    assert report["files"][0]["runtimeExit"] == 0
    instances = report["files"][0]["instances"]
    assert instances[0]["result"] == "recorded"
    assert instances[1]["exclusions"][0].endswith("unsupported setting: foreign_keys")
    assert instances[2]["exclusions"][0].endswith("unsupported setting: ignore_check_constraints")
    assert "test changed the controlled clock" in instances[3]["exclusions"]
    assert "test changed the controlled clock" in instances[4]["exclusions"]
    assert instances[5]["result"] == "recorded"
    _, records = load(output)
    assert records[0]["nativeVersion"] == 4
    assert all(event["clockUnixMilliseconds"] == 1700000000000 for event in records[0]["trace"])
    native_replay(records, profile=profile)
    for invalid in (0, 1700000000001, 2147483648000):
        with pytest.raises(ValueError, match="Tcl capture clock"):
            pilot(Path(fixture), upstream, output, 10, profile=profile, clock=invalid)


@pytest.mark.parametrize("source,accepted", [
    ("upstream_helper_calls.test", {"helper-mixed-1", "helper-pure-row-script", "helper-pure-returning-script"}),
    ("upstream_context_calls.test", {"context-recovered"}),
    ("upstream_attachment_calls.test", {"attachment-recovered", "attachment-boundary"}),
    ("upstream_nondeterminism_calls.test", {"nondeterminism-reset"}),
])
def test_real_helpers_and_context_recovery(tmp_path: Path, source: str, accepted: set[str]) -> None:
    """Real Tcl recovery records only verified cases and retains every refusal."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name(source), upstream / "test/context.test")
    output = tmp_path / "capture"
    report = pilot(Path(fixture), upstream, output, 10, ("context.test",))
    instances = report["files"][0]["instances"]
    assert {item["id"] for item in instances if item["result"] == "recorded"} == accepted, instances
    assert all(item["exclusions"] for item in instances if item["id"] not in accepted)
    if source == "upstream_nondeterminism_calls.test":
        assert all(item["exclusions"] == ["native acquisition: Excluded connection context: nondeterministic function: random"]
                   for item in instances[:2])
    _, records = load(output)
    native_replay(records)


def test_real_method_aliases_and_untraced_context_refusals(tmp_path: Path) -> None:
    """Canonical Tcl methods preserve helpers while callbacks and BLOB contexts stay excluded."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_fidelity_calls.test"), upstream / "test/fidelity.test")
    output = tmp_path / "capture"
    report = pilot(Path(fixture), upstream, output, 20, ("fidelity.test",))
    assert report["files"][0]["runtimeExit"] == 0, report["files"]
    instances = {item["id"]: item for item in report["files"][0]["instances"]}
    accepted = {"fidelity-helper-abbreviations", "fidelity-method-resolution", "fidelity-reset-clean",
                "fidelity-close-alias", "fidelity-auxiliary-alias", "fidelity-quoted-binding-text"}
    assert {key for key, item in instances.items() if item["result"] == "recorded"} == accepted
    for name in ("fidelity-function-alias", "fidelity-function-full", "fidelity-nested"):
        assert "application callback: function" in instances[name]["exclusions"]
    assert "nested SQL execution" in instances["fidelity-nested"]["exclusions"]
    assert "application callback: collate" in instances["fidelity-collate"]["exclusions"]
    assert "incremental BLOB operation: sqlite3_blob_write" in instances["fidelity-blob-api"]["exclusions"]
    assert "incremental BLOB operation: incrblob" in instances["fidelity-blob-method"]["exclusions"]
    for name in ("fidelity-untraced-prefix-bind", "fidelity-untraced-sql-bind"):
        assert instances[name]["exclusions"] == ["implicit Tcl parameter binding: $bind_value"]
    assert "connection command renamed" in instances["fidelity-reset-renamed-live"]["exclusions"]
    _, records = load(output)
    native_replay(records)


def test_size_exclusion_preserves_quota_and_native_evidence(tmp_path: Path) -> None:
    """An oversized logical case is named with bytes; the next case uses the quota."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_storage_calls.test"), upstream / "test/storage.test")
    output = tmp_path / "capture"
    report = pilot(Path(fixture), upstream, output, 1, ("storage.test",))
    assert report["files"][0]["runtimeExit"] == 0
    oversized, small = report["files"][0]["instances"]
    assert oversized["id"] == "storage-oversized"
    assert oversized["exclusions"] == ["case size limit"]
    assert oversized["caseByteCount"] > 1_000_000
    assert small["result"] == "recorded"
    stored = json.loads(gzip.decompress((output / "cases.jsonl.gz").read_bytes()))
    assert stored["snapshotStorageVersion"] == 1
    assert len(stored["snapshots"]) == 1
    _, records = load(output)
    assert records[0]["name"] == "storage:storage-small:1"
    native_replay(records)
