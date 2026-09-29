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
