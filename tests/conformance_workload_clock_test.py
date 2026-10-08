"""The directory inventory carries the same controlled clock into defaults and triggers."""

import json
from pathlib import Path
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.native_bindings import decode_rows
from conformance.workload import bound_records, record

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_directory_controlled_clock_and_refused_extra_inputs(tmp_path: Path) -> None:
    """Freeze reached clock inputs exactly; malformed and unexecuted inputs never freeze."""
    source = tmp_path / "input"
    shutil.copytree(ROOT / "conformance/synthetic-workload", source)
    profile = json.loads((source / "profile.json").read_text())
    profile["clock"] = "unix-milliseconds-v1"
    (source / "profile.json").write_text(json.dumps(profile))
    (source / "schema.sql").write_text("CREATE TABLE t(stamp DEFAULT(unixepoch())); CREATE TABLE audit(stamp);"
        "CREATE TRIGGER log AFTER INSERT ON t BEGIN INSERT INTO audit VALUES(unixepoch()); END;")
    (source / "transaction.sql").write_text("INSERT INTO t DEFAULT VALUES RETURNING stamp; SELECT stamp,unixepoch() FROM audit;")
    (source / "empty.sql").write_text("SELECT unixepoch();")
    value = {"workloadFormatVersion": 1, "profile": "profile.json", "setup": ["schema.sql"],
        "setupClockUnixMilliseconds": 1699999999000,
        "cases": [{"name": "clock-default-trigger", "sql": "transaction.sql", "features": ["controlled-clock"],
            "parameters": [[], []], "clockUnixMilliseconds": [1700000000000, 1700000001000]},
            {"name": "clock-query", "sql": "empty.sql", "features": ["controlled-clock"],
             "parameters": [[]], "clockUnixMilliseconds": [1700000002000]}]}
    (source / "workload.json").write_text(json.dumps(value))
    record(source, tmp_path / "frozen")
    _, records = bound_records(source, tmp_path / "frozen")
    assert decode_rows(records[0]["trace"][0]["rows"]) == [((1, 1700000000),)]
    assert decode_rows(records[0]["trace"][1]["rows"]) == [((1, 1700000000), (1, 1700000001))]
    native_replay(records)
    for clocks in ([True, 1700000001000], [2**63, 1700000001000], [],
                   [1700000000000, 1700000001000, 1700000002000]):
        value["cases"][0]["clockUnixMilliseconds"] = clocks
        (source / "workload.json").write_text(json.dumps(value))
        with pytest.raises(ValueError, match="[Cc]lock|date range"):
            record(source, tmp_path / "never-frozen")
        assert not (tmp_path / "never-frozen").exists()
    assert load(tmp_path / "frozen")[1] == records
