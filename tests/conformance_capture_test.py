"""Real pinned Tcl capture establishes profiles before cross-engine fidelity checks."""

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
    assert report["recordedCases"] == 1, report["files"]
    instances = report["files"][0]["instances"]
    assert instances[0]["result"] == "recorded"
    assert "test changed the controlled clock" in instances[1]["exclusions"]
    _, records = load(output)
    assert records[0]["nativeVersion"] == 4
    assert all(event["clockUnixMilliseconds"] == 1700000000000 for event in records[0]["trace"])
    native_replay(records, profile=profile)
    for invalid in (0, 1700000000001, 2147483648000):
        with pytest.raises(ValueError, match="Tcl capture clock"):
            pilot(Path(fixture), upstream, output, 10, profile=profile, clock=invalid)
