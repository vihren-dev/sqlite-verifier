"""Pinned Tcl capture distinguishes restored FK context from a real database reset."""

from pathlib import Path
import os
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.native_record import record_sql
from conformance.upstream_pilot import pilot
from conformance.upstream_profiles import catalog_profiles

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def fixture() -> Path:
    """Use the pinned harness supplied by the Nix upstream test target."""
    executable = shutil.which("testfixture")
    if executable is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    return Path(executable)


def source(tmp_path: Path, body: str) -> Path:
    """Run scenario SQL through the actual pinned tester.tcl procedures."""
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    (upstream / "test/fkey_recovery.test").write_text(
        "set testdir [file join $env(CONFORMANCE_UPSTREAM) test]\n"
        "source [file join $testdir tester.tcl]\nreset_db\n" + body + "\nfinish_test\n")
    return upstream


def test_restoration_retains_database_dependencies(tmp_path: Path) -> None:
    """OFF history recovers only after restoration, preserving the orphan row it created."""
    upstream = source(tmp_path, """
do_test fk-off {
  db eval {PRAGMA foreign_keys=OFF;
    CREATE TABLE p(id PRIMARY KEY); CREATE TABLE c(id REFERENCES p);
    INSERT INTO c VALUES(7); SELECT id FROM c}
} 7
do_test fk-still-off {db eval {SELECT id FROM c}} 7
db eval {BEGIN; PRAGMA foreign_keys=ON}
do_test fk-open-transaction {db eval {PRAGMA foreign_keys}} 0
db eval {COMMIT; PRAGMA foreign_keys=ON}
do_test fk-restored {db eval {SELECT id FROM c; PRAGMA foreign_keys}} {7 1}
do_test fk-restored-enforcement {catchsql {INSERT INTO c VALUES(8)}} {1 {FOREIGN KEY constraint failed}}
reset_db
do_test fk-reset {db eval {SELECT count(*) FROM sqlite_schema; PRAGMA foreign_keys}} {0 1}
""")
    output = tmp_path / "capture"
    report = pilot(fixture(), upstream, output, None, ("fkey_recovery.test",), catalog_profile_policy=True)
    observed = report["files"][0]
    assert observed["runtimeExit"] == 0 and observed["runtimeComplete"], observed
    results = {item["id"]: item["result"] for item in observed["instances"]}
    assert "unsupported setting: foreign_keys" in results["fk-off"]
    assert "setting readback differs: foreign_keys" in results["fk-still-off"]
    assert "outside a transaction" in results["fk-open-transaction"]
    assert {name for name, result in results.items() if result == "recorded"} == {
        "fk-restored", "fk-restored-enforcement", "fk-reset"}
    _, records = load(output)
    restored, enforced, reset = records
    original = restored["minimization"]["originalSetupCommands"]
    assert any("PRAGMA foreign_keys=OFF" in command for command in original)
    assert any("COMMIT; PRAGMA foreign_keys=ON" in command for command in original)
    assert any("INSERT INTO c VALUES(7)" in command for command in restored["setupCommands"])
    assert restored["upstream"]["expectedTcl"] == "7 1"
    assert restored["trace"][0]["rows"] == [[{"integer": {"value": 7}}]]
    assert enforced["trace"][-1]["error"] == "FOREIGN KEY constraint failed"
    assert reset["minimization"]["originalSetupCommands"] == []
    native_replay(records)


@pytest.mark.parametrize("enabled", [False, True])
def test_transaction_setting_writes_are_actual_noops(tmp_path: Path, enabled: bool) -> None:
    """Both directions preserve readback, SQL text and fresh native observations."""
    upstream = source(tmp_path, f"""
do_test fk-local {{db eval {{BEGIN; PRAGMA foreign_keys={int(not enabled)};
    PRAGMA foreign_keys; COMMIT; PRAGMA foreign_keys}}}} {{{int(enabled)} {int(enabled)}}}
""")
    profile = catalog_profiles()["upstream-fkey-deferred" if enabled else "upstream-default-deferred"]
    output = tmp_path / "capture"
    report = pilot(fixture(), upstream, output, None, ("fkey_recovery.test",), profile=profile)
    assert report["recordedCases"] == 1, report["files"]
    _, records = load(output)
    assert f"PRAGMA foreign_keys={int(not enabled)}" in records[0]["migrationSql"]
    assert [records[0]["trace"][index]["rows"] for index in (2, 4)] == [
        [[{"integer": {"value": int(enabled)}}]]] * 2
    native_replay(records)
    with pytest.raises(ValueError, match="unsupported setting: foreign_keys"):
        record_sql("", f"PRAGMA foreign_keys={int(not enabled)};", name="actual-change",
                   outputs=True, profile=profile)
