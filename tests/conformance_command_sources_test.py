"""Native and Tcl results expose assembly errors as well as ordinary SQL behavior."""

import os
from pathlib import Path
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.native_record import record_sql
from conformance.upstream_helpers import command_events, join_commands
from conformance.upstream_pilot import pilot

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_explain_retains_original_sql_source() -> None:
    """Adding call separators cannot add a newline to EXPLAIN's CREATE INDEX operand."""
    commands = ["EXPLAIN CREATE INDEX i ON t(a)", "SELECT 1"]
    direct = record_sql("CREATE TABLE t(a)", commands[0], name="direct", outputs=True)
    assembled = record_sql("CREATE TABLE t(a)", join_commands(commands), name="assembled", outputs=True)
    assert assembled["trace"][0]["rows"] == direct["trace"][0]["rows"]
    assert [len(group) for group in command_events(assembled, commands)] == [1, 1]


@pytest.mark.parametrize("command", [
    "SELECT 7 -- EOF", "SELECT 7 /*closed*/", "SELECT '--quoted /*text*/'", "SELECT 'é' -- EOF",
])
def test_comment_boundaries_keep_both_calls(command: str) -> None:
    """Comments and UTF-8 offsets cannot absorb the next call or change its grouping."""
    commands = [command, "SELECT 2"]
    direct = record_sql("", command, name="direct", outputs=True)
    assembled = record_sql("", join_commands(commands), name="assembled", outputs=True)
    assert assembled["trace"][0]["rows"] == direct["trace"][0]["rows"]
    assert [len(group) for group in command_events(assembled, commands)] == [1, 1]
    assert assembled["trace"][1]["rows"] == [[{"integer": {"value": 2}}]]
    for separator in ("\n", "\n;\n"):
        historical = record_sql("", separator.join(["SELECT 1;", "SELECT 2;"]), name="old")
        assert [len(group) for group in command_events(historical, ["SELECT 1;", "SELECT 2;"])] == [1, 1]


def test_unterminated_comment_cannot_hide_a_call() -> None:
    """SQLite permits EOF block comments, but concatenation cannot reproduce separate calls."""
    with pytest.raises(ValueError, match="unterminated block comment"):
        join_commands(["SELECT 1 /* EOF", "SELECT 2"])


def test_real_tcl_source_observations(tmp_path: Path) -> None:
    """The pinned Tcl/native cross-check agrees on EXPLAIN, EOF and quoted comments."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    source = tmp_path / "upstream" / "test"
    source.mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_source_calls.test"), source / "source.test")
    output = tmp_path / "capture"
    report = pilot(Path(fixture), source.parent, output, None, ("source.test",))
    assert report["files"][0]["runtimeExit"] == 0
    assert report["files"][0]["runtimeComplete"] is True
    assert report["recordedCases"] == 3, report["files"]
    assert all(row["result"] == "recorded" for row in report["files"][0]["instances"])
    _, records = load(output)
    native_replay(records)
