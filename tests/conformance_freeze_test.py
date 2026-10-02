"""Generic freezing requires complete, reproducible acquisition and retained triage evidence."""

from copy import deepcopy
import gzip
import json
from pathlib import Path

import pytest

from conformance.authored_cases import AuthoredCase
from conformance.case_format import Json
from conformance.corpus import load, native_replay
import conformance.freeze_corpus as finalizer
from conformance.freeze_validation import ARCHIVE_SHA256, EXTRACTOR_FILES, digest
from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, SOURCE_ID, library_path, load_library
from conformance.native_record import record_sql
from conformance.native_storage import serialized, shared_record
from conformance.upstream_catalog import catalog_patterns, exclusion_policy, source_catalog
from conformance.upstream_sampling import EXPRESSION_COHORTS, sampling_policy, select_candidates

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def save(directory: Path, report: dict[str, Json], record: dict[str, Json]) -> None:
    """Rebind the input transport when testing selection rather than a stale outer digest."""
    payload = serialized(record) + b"\n"
    report["casesSha256"] = digest(payload)
    (directory / "cases.jsonl.gz").write_bytes(gzip.compress(payload, mtime=0))
    (directory / "manifest.json").write_bytes(serialized(report))


@pytest.fixture
def capture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path, dict[str, Json], dict[str, Json]]:
    """A synthetic complete 55-source scan uses real typed evidence and minimal authored stand-ins."""
    directory, upstream = tmp_path / "capture", tmp_path / "upstream"
    directory.mkdir()
    (upstream / "test").mkdir(parents=True)
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="freeze-probe")
    finally:
        connection.close()
    record = record_sql("", "SELECT ? AS value;", name="probe", outputs=True,
        parameters=[((4, b"\x00\xff"),)], profile=profile)
    record.update(part="upstream", features=["expressions", "real-arithmetic", "coalesce", "cast"],
                  featureMetadataScope="source-file")
    files: list[dict[str, Json]] = []
    for declaration in source_catalog():
        path = upstream / "test" / declaration["file"]
        path.write_text("# synthetic reviewed source\n")
        file = {**declaration, "sha256": digest(path.read_bytes())}
        if declaration["fileExclusions"]:
            file["excludedFile"] = "; ".join(declaration["fileExclusions"])
        else:
            instances = [{"id": "probe", "occurrence": 0, "result": "recorded", "exclusions": []}]
            instances = instances if declaration["file"] == "expr.test" else []
            file.update(runtimeExit=0, runtimeComplete=True, runtimeAssertions=len(instances), recorded=len(instances),
                reasons={"recorded": 1} if instances else {}, instances=instances,
                expressionSampling=select_candidates(declaration["file"], instances, EXPRESSION_COHORTS)[1])
        files.append(file)
    record["upstream"] = {"file": "expr.test", "id": "probe", "occurrence": 0,
                          "sourceSha256": next(file["sha256"] for file in files if file["file"] == "expr.test")}
    report: dict[str, Json] = {"corpusVersion": 1, "recordedCases": 1, "sourceId": SOURCE_ID,
        "sourceRelease": "3.51.0", "sourceArchiveSha256": ARCHIVE_SHA256, "perFileLimit": None,
        "patterns": list(catalog_patterns()), "sourceCatalogVersion": 1, "sourceCatalog": source_catalog(),
        "fileExclusionPolicy": exclusion_policy(), "expressionSamplingPolicy": sampling_policy(EXPRESSION_COHORTS),
        "executionProfiles": [profile.to_wire()], "files": files,
        "extractorSha256": {name: digest((ROOT / "conformance" / name).read_bytes()) for name in EXTRACTOR_FILES}}
    save(directory, report, shared_record(record))
    def authored(cases: list[AuthoredCase] | None = None) -> list[dict[str, Json]]:
        """Keep fresh native round trips while avoiding repeated acquisition of the full tested catalog."""
        parts = ["boundary-interaction", "requirement"] if cases is None else ["boundary-interaction"]
        return [{**deepcopy(record), "name": f"authored-{index}" if cases is None else "issue-case", "part": part,
                 "upstream": {}, "features": ["typed-parameters"]} for index, part in enumerate(parts)]
    monkeypatch.setattr(finalizer, "authored_records", authored)
    return directory, upstream, report, record


def test_complete_freeze_replays_and_binds_actual_artifacts(capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
                                                         tmp_path: Path) -> None:
    """Ordered source shards, original extraction, build hashes and exact measured bytes survive load."""
    directory, upstream, report, record = capture
    next(file for file in report["files"] if file["file"] == "expr.test").update(runtimeExit=1, runtimeComplete=True)
    save(directory, report, shared_record(record))
    output = tmp_path / "frozen"
    manifest = finalizer.freeze(directory, output, upstream=upstream)
    loaded_manifest, cases = load(output)
    assert loaded_manifest == manifest and len(cases) == 4
    assert [(shard["source"], shard["part"]) for shard in manifest["shards"]] == [
        ("authored", "boundary-interaction"), ("authored", "requirement"),
        ("issue-boundaries", "issue-boundary"), ("expr.test", "upstream")]
    native_replay(cases)
    retained = (output / "extraction.json.gz").read_bytes()
    assert digest(retained) == manifest["extraction"]["sha256"]
    assert gzip.decompress(retained) == (directory / "manifest.json").read_bytes()
    assert manifest["sourceHashes"] == finalizer.code_hashes()
    assert len(manifest["sourceFiles"]) == 55 and manifest["byPart"]["issue-boundary"] == 1
    assert manifest["freezeStatistics"]["directoryBytes"] == sum(path.stat().st_size for path in output.rglob("*") if path.is_file())


@pytest.mark.parametrize("damage", ["catalog", "limit", "timeout", "incomplete", "count", "sampling", "source", "version", "extractor", "missing-completion", "false-completion"])
def test_refuses_incomplete_or_changed_acquisition(capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
                                                tmp_path: Path, damage: str) -> None:
    """Policy and candidate accounting cannot change while accepted SQL remains the same."""
    directory, upstream, report, record = capture
    file = next(file for file in report["files"] if file["file"] == "expr.test")
    if damage == "catalog": report["sourceCatalog"].pop()
    elif damage == "limit": report["perFileLimit"] = 20
    elif damage == "timeout": file["timedOut"] = True
    elif damage == "incomplete": file.update(runtimeExit=1, runtimeComplete=False)
    elif damage == "count": file["runtimeAssertions"] = True
    elif damage == "sampling": report["expressionSamplingPolicy"]["cohorts"].pop()
    elif damage == "source": (upstream / "test/expr.test").write_text("changed\n")
    elif damage == "version": record["nativeVersion"] = 3
    elif damage == "extractor": report["extractorSha256"].pop("native_record.py")
    elif damage == "missing-completion": del file["runtimeComplete"]
    elif damage == "false-completion": file["runtimeComplete"] = False
    save(directory, report, shared_record(record))
    with pytest.raises(ValueError): finalizer.freeze(directory, tmp_path / "frozen", upstream=upstream)
    assert not (tmp_path / "frozen").exists()


def test_all_retained_versions_are_required(tmp_path: Path) -> None:
    """A budget denominator cannot silently omit a historical frozen corpus."""
    with pytest.raises(ValueError, match="all be accounted"):
        finalizer.retained_bytes(())


def test_refuses_oversized_or_changed_native_evidence(capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
                                                   tmp_path: Path) -> None:
    """Logical size and a fresh native result are independent final membership gates."""
    directory, upstream, report, record = capture
    record["padding"] = "x" * 1_000_000
    save(directory, report, record)
    with pytest.raises(ValueError, match="case size limit"):
        finalizer.freeze(directory, tmp_path / "frozen", upstream=upstream)
    del record["padding"]
    record["trace"][0]["rows"] = []
    save(directory, report, shared_record(record))
    with pytest.raises(ValueError, match="Native replay changed"):
        finalizer.freeze(directory, tmp_path / "frozen", upstream=upstream)
    assert not (tmp_path / "frozen").exists()


@pytest.mark.parametrize("damage", ["none", "missing", "digest", "identity", "cause", "evidence"])
def test_mismatches_need_complete_bound_evidence(capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
                                               tmp_path: Path, damage: str) -> None:
    """A named cause counts only when its precise acquisition and supporting bytes are retained."""
    directory, upstream, report, record = capture
    file = next(file for file in report["files"] if file["file"] == "check.test")
    reason = "native acquisition: prefix results differ from Tcl execution"
    file.update(runtimeAssertions=1, reasons={reason: 1}, instances=[
        {"id": "mismatch", "occurrence": 0, "result": reason, "exclusions": [reason]}])
    save(directory, report, shared_record(record))
    proof = tmp_path / "proof.txt"
    proof.write_text("Measured independent Tcl and native path observations.\n")
    ledger = {"ledgerVersion": 1, "extractionSha256": digest((directory / "manifest.json").read_bytes()),
              "entries": [{"file": "check.test", "id": "mismatch", "occurrence": 0,
                           "cause": "filesystem path observation", "evidence": [{"path": "proof.txt", "sha256": digest(proof.read_bytes())}]}]}
    if damage == "digest": ledger["extractionSha256"] = "0" * 64
    elif damage == "identity": ledger["entries"][0]["occurrence"] = True
    elif damage == "cause": ledger["entries"][0]["cause"] = " "
    elif damage == "evidence": proof.write_text("altered proof")
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_bytes(serialized(ledger))
    if damage == "none":
        manifest = finalizer.freeze(directory, tmp_path / "frozen", upstream=upstream, fidelity_ledger=ledger_path)
        assert manifest["fidelityLedger"]["mismatches"] == 1
        assert (tmp_path / "frozen/fidelity/proof.txt").read_bytes() == proof.read_bytes()
    else:
        with pytest.raises(ValueError):
            finalizer.freeze(directory, tmp_path / "frozen", upstream=upstream,
                             fidelity_ledger=None if damage == "missing" else ledger_path)
        assert not (tmp_path / "frozen").exists()


@pytest.mark.parametrize("budget", ["CURRENT_BYTE_LIMIT", "RETAINED_BYTE_LIMIT"])
def test_budget_refusal_preserves_destination(capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
                                            tmp_path: Path, monkeypatch: pytest.MonkeyPatch, budget: str) -> None:
    """Actual output bytes and historical artifacts must fit before publishing any final directory."""
    directory, upstream, _report, _record = capture
    old = tuple(tmp_path / f"retained-v{version}" for version in (1, 2, 3))
    for version, path in enumerate(old, 1):
        path.mkdir()
        (path / "manifest.json").write_bytes(serialized({"corpusVersion": version}))
        (path / "evidence.gz").write_bytes(b"old frozen evidence")
    monkeypatch.setattr(finalizer, budget, 1)
    with pytest.raises(ValueError, match="budget"):
        finalizer.freeze(directory, tmp_path / "frozen", upstream=upstream, retained=old)
    assert not (tmp_path / "frozen").exists()
