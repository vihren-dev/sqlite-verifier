"""Runtime event extraction preserves loops, errors and native minimization truth."""

from pathlib import Path
import pytest
from conformance.upstream_pilot import assertions
from conformance.upstream_fidelity import check_results, minimize_prefix
from conformance.native_record import record_sql

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_runtime_instances_and_extraction_fidelity() -> None:
    """Expanded names remain distinct; redundant setup shrinks without changing native truth."""
    events = [("reset",), ("sql", "db", "CREATE TABLE t(x);", "0", "eval"), ("result", "db", "0")]
    for i in range(3):
        events += [("begin", f"loop-{i}", str(i)),
                   ("sql", "db", f"SELECT {i};", "0", "eval"),
                   ("result", "db", "0", str(i)), ("end", f"loop-{i}")]
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    candidates = assertions(encoded)
    assert [case["id"] for case in candidates] == ["loop-0", "loop-1", "loop-2"]
    candidate = candidates[-1]
    record = record_sql(candidate["prefix"], "\n".join(candidate["commands"]), name="loop")
    check_results(record, candidate)
    minimized = minimize_prefix(record)
    assert minimized["setupCommands"] == ["CREATE TABLE t(x);"]
    assert minimized["initial"] == record["initial"] and minimized["trace"] == record["trace"]
    candidate["results"] = [["wrong"]]
    with pytest.raises(ValueError, match="assertion results differ"):
        check_results(record, candidate)


@pytest.mark.parametrize("controlled", [False, True])
def test_minimization_preserves_output_and_profile_evidence(tmp_path: Path, controlled: bool) -> None:
    """Deleting redundant setup retains parameter bindings, output format and controlled time."""
    from conformance.execution_profile import measured_profile
    from conformance.native_connection import Connection, load_library, library_path
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="minimization-clock", clock="unix-milliseconds-v1") if controlled else None
    finally:
        connection.close()
    record = record_sql(["CREATE TABLE t(v);", "SELECT 99;"],
        "SELECT ?1" + (",unixepoch()" if controlled else "") + ";", name="minimize-outputs",
        outputs=True, parameters=[((1, 7),)], profile=profile,
        setup_clock=1700000000000 if controlled else None,
        clock_values=[1700000001000] if controlled else None)
    minimized = minimize_prefix(record)
    assert minimized["setupCommands"] == ["CREATE TABLE t(v);"]
    assert minimized["nativeVersion"] == record["nativeVersion"]
    assert (minimized["initial"], minimized["trace"]) == (record["initial"], record["trace"])
    if controlled:
        assert minimized["profile"] == record["profile"]
        assert minimized["setupClockUnixMilliseconds"] == record["setupClockUnixMilliseconds"]


def test_frozen_corpus_replays(runtime_root: Path) -> None:
    """The frozen denominator replays natively and never loses admitted agreements."""
    from conformance.corpus import load, native_replay, replay
    _, records = load(Path(__file__).resolve().parents[1] / "conformance/corpus-v1")
    assert len(records) == 177
    native_replay(records)
    progress = replay(records, runtime_root)
    assert progress == replay(records, runtime_root)
    assert progress["counts"].get("AGREE", 0) >= 2
    assert not progress["counts"].get("DISAGREE", 0)
    assert not progress["counts"].get("HARNESS_ERROR", 0)


def test_reopen_preserves_commit_and_discards_pending_write() -> None:
    """A real close/reopen boundary retains committed rows and rolls back pending rows."""
    events = [("reset", "/tmp/test.db"),
              ("sql", "db", "CREATE TABLE t(v); INSERT INTO t VALUES(1); BEGIN; INSERT INTO t VALUES(2);", "0", "eval"),
              ("result", "db", "0"), ("close", "db"), ("open", "db", "/tmp/test.db"),
              ("config", "db", "SQLITE_DBCONFIG_DQS_DDL", "1"),
              ("begin", "after-reopen", "1"), ("sql", "db", "SELECT * FROM t;", "0", "eval"),
              ("result", "db", "0", "1"), ("end", "after-reopen")]
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    candidate = assertions(encoded)[0]
    assert not candidate["exclusions"]
    record = record_sql(candidate["prefix"], "\n".join(candidate["commands"]), name="reopen")
    check_results(record, candidate)
    assert record["nativeVersion"] == 2
    assert record["trace"][0]["rows"] == [[{"integer": {"value": 1}}]]
    assert not record["initial"]["transactionOpen"]
    memory_events = encoded.replace("/tmp/test.db".encode().hex(), ":memory:".encode().hex())
    assert "memory database reopened without reset_db" in assertions(memory_events)[0]["exclusions"]


def test_nearest_requirement_context() -> None:
    """Record local comment lines without crediting every requirement mentioned in the file."""
    from conformance.upstream_evidence import evidence
    source = "# EVIDENCE-OF: R-00001-00002 old\ndo_test old {} {}\n# EVIDENCE-OF: R-00003-00004 current\n# continued\ndo_test new {} {}\n"
    assert evidence(source, 5) == [{"id": "R-00003-00004", "line": 3}]


def test_selection_cap_preserves_context_and_fidelity_reasons() -> None:
    """A capped candidate still exposes all the reasons it cannot be recovered."""
    from conformance.upstream_selection import candidate_reasons
    candidate = {"exclusions": ["multiple connections", "configuration outside profile: X"],
                 "failed": True, "commands": [], "codes": [1, 0], "implicitBindingReasons": []}
    expected = {"multiple connections", "configuration outside profile: X",
                "upstream Tcl expectation failed", "no SQL observation",
                "assertion continues after a SQL error"}
    assert set(candidate_reasons(candidate, selected=0, limit=1)) == expected
    assert set(candidate_reasons(candidate, selected=1, limit=1)) == expected | {"bounded pilot selection limit"}
    candidate = {"exclusions": [], "failed": False, "commands": ["SELECT 1;"], "codes": [0], "implicitBindingReasons": []}
    assert candidate_reasons(candidate, selected=0, limit=1) == []


@pytest.mark.parametrize("helper,sql,expected", [("exists", "SELECT 42;", "1"),
    ("exists", "SELECT 42 WHERE 0;", "0"), ("onecolumn", "SELECT 42,99 UNION ALL SELECT 7,8;", "42"),
    ("onecolumn", "SELECT NULL;", ""), ("onecolumn", "SELECT 42 WHERE 0;", "")])
def test_helper_results_keep_ordinary_native_rows(helper: str, sql: str, expected: str) -> None:
    """Tcl helper expectations differ from native rows; evidence stays unmodified."""
    events = [("reset",), ("sql", "db", "SELECT 12,13;", "0", "onecolumn"),
              ("result", "db", "0", "12"), ("begin", "helper", expected),
              ("sql", "db", sql, "0", helper), ("result", "db", "0", expected),
              ("result-nullvalue", "db", ""), ("end", "helper")]
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    candidate = assertions(encoded)[0]
    assert not candidate["exclusions"]
    record = record_sql(candidate["prefix"], sql, name="helper",
                        setup_helpers=candidate["prefixHelpers"], migration_readonly=True)
    check_results(record, candidate)
    if sql == "SELECT 42;":
        assert record["trace"][0]["rows"] == [[{"integer": {"value": 42}}]]
    candidate["results"] = [["wrong"]]
    with pytest.raises(ValueError, match="assertion results differ"):
        check_results(record, candidate)


def test_row_helpers_refuse_writes_and_row_scripts() -> None:
    """No helper shortcut can execute writes or silently accept Tcl script side effects."""
    for sql in ("INSERT INTO t VALUES(1) RETURNING x;", "PRAGMA user_version=1;"):
        with pytest.raises(ValueError, match="read-only SELECT"):
            record_sql("CREATE TABLE t(x);", sql, name="writing-helper", migration_readonly=True)
    events = [("reset",), ("begin", "script", ""),
              ("sql", "db", "SELECT 1;", "1", "eval"), ("result", "db", "0", ""), ("end", "script")]
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    assert "connection or SQL callback context" in assertions(encoded)[0]["exclusions"]


def test_mixed_helpers_keep_call_boundaries() -> None:
    """Writes, multi-statement eval and different row helpers compare per Tcl call."""
    from conformance.upstream_helpers import readonly_spans, command_events, join_commands
    commands = ["-- é\nCREATE TABLE t(x); INSERT INTO t VALUES(42),(7); -- trailing",
                "SELECT x,99 FROM t ORDER BY x DESC", "SELECT 42", "SELECT x FROM t ORDER BY x"]
    helpers = ["eval", "onecolumn", "exists", "eval"]
    results = [[], ["42"], ["1"], ["7", "42"]]
    events = [("reset",), ("begin", "mixed", "")]
    for command, helper, expected in zip(commands, helpers, results, strict=True):
        events += [("sql", "db", command, "0", helper), ("result", "db", "0", *expected)]
    events += [("end", "mixed")]
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    candidate = assertions(encoded)[0]
    record = record_sql([], join_commands(commands), name="mixed", migration_readonly_spans=readonly_spans(commands, helpers))
    check_results(record, candidate)
    assert [len(group) for group in command_events(record, commands)] == [2, 1, 1, 1]
    assert record["trace"][3]["rows"] == [[{"integer": {"value": 42}}]]
    candidate["results"][1] = ["7"]
    with pytest.raises(ValueError, match="assertion results differ"):
        check_results(record, candidate)
    bad = ["CREATE TABLE t(x);", "INSERT INTO t VALUES(1) RETURNING x;"]
    with pytest.raises(ValueError, match="read-only SELECT"):
        record_sql([], join_commands(bad), name="mixed-write", migration_readonly_spans=readonly_spans(bad, ["eval", "onecolumn"]))
    combined = record_sql([], "SELECT\n42;", name="cross-call")
    with pytest.raises(ValueError, match="crosses Tcl SQL call"):
        command_events(combined, ["SELECT", "42;"])


def test_pure_row_script_semantics_keep_returning_rows() -> None:
    """Pure Tcl bodies return empty output while native write/RETURNING evidence survives."""
    events = [("reset",), ("sql", "db", "CREATE TABLE t(x);", "0", "eval"),
              ("result", "db", "0"), ("begin", "pure", ""),
              ("sql", "db", "INSERT INTO t VALUES(3) RETURNING x;", "0", "eval-script"),
              ("result", "db", "0"), ("end", "pure")]
    encoded = "\n".join("\t".join(value.encode().hex() for value in event) for event in events)
    candidate = assertions(encoded)[0]
    assert not candidate["exclusions"]
    record = record_sql(candidate["prefix"], candidate["commands"][0], name="pure")
    check_results(record, candidate)
    assert record["trace"][0]["rows"] == [[{"integer": {"value": 3}}]]
