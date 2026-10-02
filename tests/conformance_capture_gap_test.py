"""Real Tcl capture preserves errors, control lifetimes and source completion evidence."""

import os
from pathlib import Path
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.upstream_pilot import pilot

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def pinned_fixture() -> Path:
    """Use the pinned executable supplied by the upstream Nix target."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    return Path(fixture)


def test_real_errors_and_external_control_lifetimes(tmp_path: Path) -> None:
    """Failed SQL keeps its error code; connection controls reset while global controls persist."""
    fixture = pinned_fixture()
    source = tmp_path / "upstream" / "test"
    source.mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_external_calls.test"), source / "external.test")
    output = tmp_path / "capture"
    report = pilot(fixture, source.parent, output, None, ("external.test",))
    file = report["files"][0]
    assert file["runtimeExit"] == 0 and file["runtimeComplete"] is True, file
    instances = {row["id"]: row for row in file["instances"]}
    accepted = {"gap-syntax-error-code", "gap-control-reset", "gap-limit-reset",
                "gap-file-reset", "gap-ordinary-reopen", "gap-unrelated-files", "gap-file-final-reset"}
    assert {name for name, row in instances.items() if row["result"] == "recorded"} == accepted
    assert not any("upstream Tcl expectation failed" in row["exclusions"] for row in instances.values())
    assert instances["gap-internal-functions"]["exclusions"] == [
        "external/configuration operation: sqlite3_test_control SQLITE_TESTCTRL_INTERNAL_FUNCTIONS"]
    assert instances["gap-connection-limit"]["exclusions"] == [
        "external/configuration operation: sqlite3_limit"]
    expected = ["external/configuration operation: sqlite3_test_control SQLITE_TESTCTRL_LOCALTIME_FAULT"]
    assert instances["gap-global-control"]["exclusions"] == expected
    assert instances["gap-global-control-reset"]["exclusions"] == expected
    for name, method in {
        "gap-file-delete": "file delete", "gap-file-delete-lifetime": "file delete",
        "gap-file-delete-alias": "file delete", "gap-file-delete-native": "file delete",
        "gap-file-copy": "file copy", "gap-file-rename": "file rename",
        "gap-file-open": "open for writing", "gap-file-touch": "file mtime",
    }.items():
        assert instances[name]["exclusions"] == ["database file operation: " + method], instances[name]
    _, records = load(output)
    native_replay(records)


@pytest.mark.parametrize("finish,exit_code,complete", [
    ("finish_test", 1, True), ("exit 1", 1, False), ("exit 0", 0, False),
])
def test_real_completion_marker_distinguishes_assertion_failure_from_abort(
        tmp_path: Path, finish: str, exit_code: int, complete: bool) -> None:
    """Only reaching finish_test proves completion when the Tcl process exits with an error."""
    fixture = pinned_fixture()
    source = tmp_path / "upstream" / "test"
    source.mkdir(parents=True)
    (source / "completion.test").write_text(
        "set testdir [file join $env(CONFORMANCE_UPSTREAM) test]\n"
        "source [file join $testdir tester.tcl]\n"
        "reset_db\ndo_test deliberate-failure {db eval {SELECT 1}} 2\n" + finish + "\n")
    report = pilot(fixture, source.parent, tmp_path / "capture", None, ("completion.test",))
    file = report["files"][0]
    assert file["runtimeExit"] == exit_code
    assert file["runtimeComplete"] is complete
    assert file["runtimeAssertions"] == 1 and file["recorded"] == 0
    assert file["instances"][0]["exclusions"] == ["upstream Tcl expectation failed"]
