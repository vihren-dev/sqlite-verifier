"""Release requirement identities, frozen progress, and measured-coverage report boundaries."""

import hashlib
import json
from pathlib import Path
import struct

import pytest
from conformance.corpus import load, native_replay
from conformance.measure_coverage import gcov_counts
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_replay import schema_sql
from conformance.progress import progress

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_lean, pytest.mark.requires_native("sqlite-parser", "sqlite3")]


def test_release_requirement_ids() -> None:
    """The full upstream requirement IDs must hash their exact normalized text."""
    inventory = json.loads((ROOT / "conformance/requirements-3.51.0.json").read_text())
    assert inventory["count"] == len(inventory["requirements"]) == 3500
    for row in inventory["requirements"]:
        digest = hashlib.md5(row["text"].encode()).digest()
        assert row["id"] == "R-" + "-".join(f"{value:05d}" for value in struct.unpack(">8H", digest))


def test_frozen_progress_and_replay(runtime_root: Path, tmp_path: Path) -> None:
    """V2 extends v1 without changing its evidence, and indexed schemas replay in dependency order."""
    _, original = load(ROOT / "conformance/corpus-v1")
    manifest, records = load(ROOT / "conformance/corpus-v2")
    assert records[:len(original)] == original and len(records) == 183
    native_replay(records[len(original):])
    for record in records[len(original):]:
        connection = Connection(load_library(library_path()), tmp_path / (record["name"] + ".db"))
        try:
            connection.execute_script(schema_sql(record["initial"]["visible"]))
        finally:
            connection.close()
    report = progress(ROOT / "conformance/corpus-v2", ROOT / "conformance/requirements-3.51.0.json", runtime_root)
    baseline = json.loads((ROOT / "reports/20260929-adr4-corpus-v2-progress.json").read_text())
    previous_agreements = {case["name"] for case in baseline["cases"] if case["verdict"] == "AGREE"}
    current_agreements = {case["name"] for case in report["cases"] if case["verdict"] == "AGREE"}
    assert previous_agreements <= current_agreements
    assert report["counts"].get("AGREE", 0) >= 8
    assert report["counts"].get("HARNESS_ERROR", 0) == report["counts"].get("DISAGREE", 0) == 0
    assert sum(report["counts"].values()) == manifest["recordedCases"]
    inventory = json.loads((ROOT / "conformance/requirements-3.51.0.json").read_text())
    assert report["requirementMatrixRows"] == inventory["count"] == 3500
    assert [row["id"] for row in report["requirementMatrix"]] == [row["id"] for row in inventory["requirements"]]
    assert any(sum(row["counts"].values()) == 0 for row in report["requirementMatrix"])


def test_gcov_reached_function_denominator() -> None:
    """Untaken arcs in reached functions count; unreachable functions do not inflate this scope."""
    report = gcov_counts("function reached called 2 returned 100% blocks executed 50%\n"
        "branch 0 taken 2\nbranch 1 taken 0\nbranch 2 never executed\n"
        "function unreached called 0 returned 0% blocks executed 0%\nbranch 0 never executed\n")
    assert report["functionsReached"] == 1 and report["functionsInReport"] == 2
    assert report["branchesTaken"] == 1 and report["branchesInReachedFunctions"] == 3


def test_parser_failure_is_not_subset_exclusion(runtime_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A timed-out or broken parser cannot turn a frozen native case into an unsupported verdict."""
    from conformance.native_replay import prepare
    from belay.sqlite.errors import SqlError
    record = load(ROOT / "conformance/corpus-v2")[1][-1]
    def failed(*args: object, **kwargs: object) -> None:
        """Inject the real parser's resource-failure category."""
        raise SqlError("UNVERIFIED", "SQL parser exceeded its time limit", source="case.sql")
    monkeypatch.setattr("conformance.native_replay.parse", failed)
    assert prepare(record, runtime_root / "build/sqlite-parser")[1]["verdict"] == "HARNESS_ERROR"


def test_review_corpus_extends_and_replays(runtime_root: Path) -> None:
    """V3 retains v2, adds scoped requirement evidence, and separates query-only blockers."""
    import gzip
    _, previous = load(ROOT / "conformance/corpus-v2")
    manifest, records = load(ROOT / "conformance/corpus-v3")
    assert records[:len(previous)] == previous
    additions = records[len(previous):]
    assert manifest["addedAuthoredCases"] == 23
    assert len(additions) == manifest["addedAuthoredCases"] + manifest["addedUpstreamCases"]
    native_replay(additions)
    extraction = gzip.decompress((ROOT / "conformance/corpus-v3/extraction.json.gz").read_bytes())
    assert hashlib.sha256(extraction).hexdigest() == manifest["upstreamManifestSha256"]
    assert any(record.get("upstream", {}).get("file", "").startswith("e_") and record["requirements"] for record in additions)
    report = progress(ROOT / "conformance/corpus-v3", ROOT / "conformance/requirements-3.51.0.json", runtime_root)
    assert report["counts"].get("HARNESS_ERROR", 0) == report["counts"].get("DISAGREE", 0) == 0
    assert sum(report["counts"].values()) == len(records)
    assert sum(any(row["counts"].values()) for row in report["requirementMatrix"]) > 40
    assert report["queryDiagnostics"]["QUERY_ONLY_CASE"] >= 4
    authored = {record["name"]: record for record in additions if "upstream" not in record}
    assert authored["numeric-text-integer"]["trace"][0]["visible"]["tables"][0]["rows"][0]["values"] == [{"integer": {"value": 1}}]
    assert authored["text-numeric-conversion"]["trace"][0]["visible"]["tables"][0]["rows"][0]["values"] == [{"text": {"bytes": [52, 50]}}]
    assert authored["create-unique-duplicate"]["trace"][0]["primaryCode"] == 19
