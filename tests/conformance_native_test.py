"""Check import fidelity and native observations without claiming a checked Lean result."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parent.parent


sys.path.insert(0, str(ROOT / "conformance"))
from native_fixture import run

pytestmark = [pytest.mark.integration, pytest.mark.conformance]


def test_upstream_pin_and_import_fidelity() -> None:
    """Imported calls preserve pinned source bytes, occurrence labels, SQL spans and Tcl expectations."""
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


@pytest.mark.parser
@pytest.mark.requires_native("sqlite-parser", "sqlite3")
@pytest.mark.parametrize("selected", range(3), ids=["alter3-3.1-1", "alter3-3.1-2", "alter3-3.2-1"])
def test_upstream_case(selected: int, runtime_root: Path) -> None:
    """A selected upstream call matches Tcl expectations after its required connection/setup prefix."""
    report = run(os.environ.get("SQLITE3", "sqlite3"), str(runtime_root / "build/sqlite-parser"), selected)
    assert [(case["upstream_id"], case["occurrence"]) for case in report["cases"]] == [
        [("alter3-3.1", 1), ("alter3-3.1", 2), ("alter3-3.2", 1)][selected]]


@pytest.mark.requires_native("sqlite3")
def test_final_native_observations(runtime_root: Path) -> None:
    """Final replay retains physical row identity, appended NULLs, the schema cookie and the inherited view."""
    report = run(os.environ.get("SQLITE3", "sqlite3"), str(runtime_root / "build/sqlite-parser"), final_only=True)
    assert report["cases"] == [], "Final replay must not repeat separately selected case comparisons"
    assert report["final_observations"][0] == [
        {"rowid": 1, "a": 1, "b": 100, "c": None},
        {"rowid": 2, "a": 2, "b": 300, "c": None}]
    assert report["final_observations"][1] == [{"schema_version": 11}]
    schema = report["final_observations"][2]
    assert [(row["type"], row["name"]) for row in schema] == [("table", "t1"), ("view", "v1")]
