"""Check import fidelity and native observations without claiming a checked Lean result."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    """Exercise original expectations, inherited state, and honest coverage/status fields."""
    upstream = ROOT / "conformance/upstream"
    hashes: dict[str, str] = json.loads((upstream / "sha256.json").read_text())
    for name, digest in hashes.items():
        assert hashlib.sha256((upstream / name).read_bytes()).hexdigest() == digest, name
    generated = subprocess.run([sys.executable, "conformance/import_fixture.py"], cwd=ROOT,
                               text=True, capture_output=True, check=True, timeout=3)
    fixture = json.loads(generated.stdout)
    assert fixture == json.loads((ROOT / "conformance/fixtures/alter3-add-null.json").read_text())
    cases = fixture["cases"]
    assert [(case["upstream_id"], case["occurrence"]) for case in cases] == [
        ("alter3-3.1", 1), ("alter3-3.1", 2), ("alter3-3.2", 1)]
    assert [case["expected_tcl"] for case in cases] == ["1 100 2 300", "", "1 100 {} 2 300 {}"]
    source = (upstream / "alter3.test").read_text().splitlines(keepends=True)
    for case in cases:
        selected = "".join(source[case["source_start_line"] - 1:case["source_end_line"]])
        assert case["sql"] in selected and case["expected_tcl"] in selected
    result = subprocess.run(
        [sys.executable, "conformance/native_fixture.py", os.environ.get("SQLITE3", "sqlite3"),
         str(ROOT / "build/sqlite-parser")], cwd=ROOT, text=True, capture_output=True,
        timeout=12, check=True)
    report = json.loads(result.stdout)
    assert report["model_status"] == "NOT_YET_MODEL_CHECKED"
    assert report["translation_status"] == "NOT_YET_TRANSLATED"
    assert all(case["native_status"] == "MATCHES_UPSTREAM" for case in report["cases"])
    assert report["final_observations"][0] == [
        {"rowid": 1, "a": 1, "b": 100, "c": None},
        {"rowid": 2, "a": 2, "b": 300, "c": None}]
    assert report["final_observations"][1] == [{"schema_version": 11}]
    schema = report["final_observations"][2]
    assert [(row["type"], row["name"]) for row in schema] == [("table", "t1"), ("view", "v1")]
    assert report["coverage"] == {"selected_call_instances": 3, "selected_distinct_ids": 2,
                                   "upstream_textual_call_sites": 59, "upstream_distinct_textual_ids": 55}
    print("conformance: 3 selected upstream assertions match pinned native observations; model unchecked")


if __name__ == "__main__":
    main()
