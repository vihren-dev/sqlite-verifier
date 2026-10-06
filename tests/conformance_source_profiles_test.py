"""Real pinned Tcl extraction verifies source routing and named callback dependency barriers."""

import os
from dataclasses import replace
from pathlib import Path
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.upstream_pilot import pilot
from conformance.upstream_profiles import catalog_profiles, profile_for_source, source_profile_policy

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def pinned_fixture() -> Path:
    """Use the fixture supplied by the isolated upstream target, never an ambient substitute."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    return Path(fixture)


def test_real_unrelated_function_and_dependent_prefix(tmp_path: Path) -> None:
    """Unused/failed registrations recover; aliases, operators, views and triggers stay excluded."""
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_registered_calls.test"), upstream / "test/registered.test")
    output = tmp_path / "capture"
    report = pilot(pinned_fixture(), upstream, output, None, ("registered.test",))
    source = report["files"][0]
    assert source["runtimeExit"] == 0, source
    accepted = {"registered-unused", "registered-failed", "registered-earlier-builtin", "registered-reset-clean",
                "registered-table-name", "registered-json-unused", "registered-json-text-unused"}
    assert {item["id"] for item in source["instances"] if item["result"] == "recorded"} == accepted, source
    assert all("application callback: function" in item["exclusions"]
               for item in source["instances"] if item["id"] not in accepted)
    _, records = load(output)
    native_replay(records)


def test_real_source_profiles_and_changed_conditions(tmp_path: Path) -> None:
    """Declared FKON reproduces cascade/deferred errors; declared time rejects source mutations."""
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    header = "set testdir [file join $env(CONFORMANCE_UPSTREAM) test]\nsource [file join $testdir tester.tcl]\nreset_db\n"
    (upstream / "test/fkey_probe.test").write_text(header + """
db eval {CREATE TABLE p(id PRIMARY KEY); CREATE TABLE c(id REFERENCES p ON DELETE CASCADE);
 INSERT INTO p VALUES(1); INSERT INTO c VALUES(1)}
do_test source-cascade {db eval {BEGIN; DELETE FROM p; SELECT count(*) FROM c; COMMIT}} 0
reset_db
db eval {CREATE TABLE p(id PRIMARY KEY); CREATE TABLE c(id REFERENCES p DEFERRABLE INITIALLY DEFERRED)}
do_test source-deferred {catchsql {BEGIN; INSERT INTO c VALUES(1); COMMIT}} {1 {FOREIGN KEY constraint failed}}
reset_db
do_test source-fk-change {db eval {PRAGMA foreign_keys=OFF; SELECT 1}} 1
finish_test
""")
    (upstream / "test/date_probe.test").write_text(header + """
do_test source-clock {db eval {SELECT unixepoch(),datetime('now')}} {1700000000 {2023-11-14 22:13:20}}
set sqlite_current_time 1700000001
do_test source-clock-change {db eval {SELECT unixepoch()}} 1700000001
finish_test
""")
    output = tmp_path / "capture"
    report = pilot(pinned_fixture(), upstream, output, None, ("fkey_probe.test", "date_probe.test"),
                   catalog_profile_policy=True)
    assert report["sourceExecutionProfilePolicy"] == source_profile_policy()
    profiles = {value["name"]: value for value in report["executionProfiles"]}
    assert len(profiles) == 4
    by_file = {file["file"]: file for file in report["files"]}
    assert all(file["runtimeExit"] == 0 and file["runtimeComplete"] for file in by_file.values()), by_file
    foreign_key, dates = by_file["fkey_probe.test"], by_file["date_probe.test"]
    assert foreign_key["executionProfile"]["name"] == "upstream-fkey-deferred"
    assert foreign_key["clockUnixMilliseconds"] is None
    assert dates["executionProfile"]["name"] == "upstream-clock-deferred"
    assert dates["clockUnixMilliseconds"] == 1700000000000
    assert [item["result"] for item in foreign_key["instances"][:2]] == ["recorded", "recorded"], foreign_key
    assert "unsupported setting: foreign_keys" in foreign_key["instances"][2]["result"]
    assert dates["instances"][0]["result"] == "recorded", dates
    assert "test changed the controlled clock" in dates["instances"][1]["exclusions"]
    _, records = load(output)
    assert len(records) == 3
    assert any(record["trace"][-1]["error"] == "FOREIGN KEY constraint failed" for record in records)
    assert all(record["profile"] == profiles[record["profile"]["name"]] for record in records)
    native_replay(records)
    with pytest.raises(ValueError, match="cannot be combined"):
        pilot(pinned_fixture(), upstream, output, None, ("date_probe.test",),
              profile=next(iter(catalog_profiles().values())), catalog_profile_policy=True)


def test_profile_primitive_remains_explicit(tmp_path: Path) -> None:
    """Caller-selected patterns retain arbitrary supported profiles and independent clock inputs."""
    profiles = catalog_profiles()
    assert profile_for_source("cast.test", profiles)[1] == 1700000000000
    assert profile_for_source("expr9.test", profiles)[1] == 1700000000000
    assert profile_for_source("alter.test", profiles)[1] is None
    assert profile_for_source("e_fkey.test", profiles)[0].foreign_keys
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    (upstream / "test/date.test").write_text("""
set testdir [file join $env(CONFORMANCE_UPSTREAM) test]
source [file join $testdir tester.tcl]
reset_db
do_test source-caller-clock {db eval {BEGIN IMMEDIATE; SELECT unixepoch(); COMMIT}} 1700001234
finish_test
""")
    profile = replace(profiles["upstream-clock-deferred"], name="caller-selected", foreign_keys=True,
                      transaction_mode="immediate")
    output = tmp_path / "capture"
    report = pilot(pinned_fixture(), upstream, output, None, ("date.test",),
                   profile=profile, clock=1700001234000)
    assert report["recordedCases"] == 1, report["files"]
    assert "sourceExecutionProfilePolicy" not in report
    _, records = load(output)
    assert records[0]["profile"] == profile.to_wire()
    assert all(event["clockUnixMilliseconds"] == 1700001234000 for event in records[0]["trace"])
    native_replay(records)
