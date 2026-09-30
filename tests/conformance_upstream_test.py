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
    from conformance.upstream_pilot import evidence
    source = "# EVIDENCE-OF: R-00001-00002 old\ndo_test old {} {}\n# EVIDENCE-OF: R-00003-00004 current\n# continued\ndo_test new {} {}\n"
    assert evidence(source, 5) == [{"id": "R-00003-00004", "line": 3}]
