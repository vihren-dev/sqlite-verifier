"""Ordinary v5 loading binds source evidence after transport digests have been recomputed."""

from copy import deepcopy
from dataclasses import replace
import gzip
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.corpus_acquisition import verify
from conformance.corpus_evidence import feature_counts
from conformance.corpus_shards import write
from conformance.freeze_validation import digest
from conformance.native_record import record_sql
from conformance.native_storage import serialized
from conformance.upstream_profiles import catalog_profiles

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture
def acquisition() -> tuple[dict[str, Json], list[dict[str, Json]]]:
    """Use measured native cases with different retained names, routing patterns and clock input."""
    profiles = [replace(profile, name=f"retained-{index}")
                for index, profile in enumerate(catalog_profiles().values())]
    clock = 1700000123000
    policy: dict[str, Json] = {"version": 1, "foreignKeyOnPatterns": ["foreign*.test"],
        "controlledClockPatterns": ["*time.test"], "clockUnixMilliseconds": clock, "transactionMode": "deferred",
        "profiles": [{"name": profile.name, "version": profile.version, "foreignKeys": profile.foreign_keys,
                      "clock": profile.clock} for profile in profiles]}
    files: list[dict[str, Json]] = []
    records: list[dict[str, Json]] = []
    precision: dict[str, Json] = {"values": [0], "successfulCalls": 1}
    nullvalue: dict[str, Json] = {"values": [""], "successfulCalls": 1}
    for filename, foreign_keys, controlled in (("ordinary.test", False, False), ("foreign-time.test", True, True)):
        profile = next(profile for profile in profiles if profile.foreign_keys == foreign_keys
                       and (profile.clock != "excluded") == controlled)
        record = record_sql("", "SELECT 123.5 AS value;", name=filename, outputs=True, profile=profile,
                            setup_clock=clock if controlled else None, clock_values=clock if controlled else None)
        sha = digest(filename.encode())
        record.update(part="upstream", features=["real-arithmetic"], featureMetadataScope="source-file",
            upstream={"file": filename, "id": "probe", "occurrence": 0, "sourceSha256": sha,
                      "tclDisplayPrecision": 0, "tclResultPrecision": deepcopy(precision),
                      "tclNullvalueEvidence": deepcopy(nullvalue)})
        records.append(record)
        files.append({"file": filename, "features": ["real-arithmetic"], "fileExclusions": [], "sha256": sha,
            "executionProfile": {"name": profile.name, "version": profile.version},
            "clockUnixMilliseconds": clock if controlled else None,
            "tclDisplayPrecision": {"original": 15, "established": 0, "requested": 0},
            "runtimeExit": 1, "runtimeComplete": True, "runtimeAssertions": 1, "recorded": 1,
            "reasons": {"recorded": 1}, "instances": [{"id": "probe", "occurrence": 0,
                "result": "recorded", "exclusions": [], "tclResultPrecision": deepcopy(precision),
                "tclNullvalueEvidence": deepcopy(nullvalue)}]})
    files.append({"file": "excluded.test", "features": [], "fileExclusions": ["file-level environment"],
                  "sha256": digest(b"excluded.test"), "excludedFile": "file-level environment"})
    report: dict[str, Json] = {"corpusVersion": 1, "recordedCases": len(records),
        "sourceRelease": profiles[0].engine_version, "sourceId": profiles[0].source_id,
        "sourceArchiveSha256": digest(b"retained archive"), "sourceCatalogVersion": 2,
        "sourceCatalog": [{key: file[key] for key in ("file", "features", "fileExclusions")} for file in files],
        "sourceFamilyPolicy": {"version": 1, "patterns": ["*.test"]}, "fileExclusionPolicy": {},
        "expressionSamplingPolicy": {}, "sourceExecutionProfilePolicy": policy,
        "tclDisplayPrecisionPolicy": {"version": 1, "requested": 0, "establishAfter": "tester.tcl"},
        "executionProfiles": [profile.to_wire() for profile in profiles], "files": files}
    return report, records


def store(directory: Path, report: dict[str, Json], records: list[dict[str, Json]], *, version: int = 5) -> None:
    """Rebind every outer digest so negative checks exercise evidence semantics rather than transport."""
    payload = serialized(report)
    compressed = gzip.compress(payload, mtime=0)
    fields = ("sourceRelease", "sourceId", "sourceArchiveSha256", "sourceCatalogVersion", "sourceCatalog",
              "sourceFamilyPolicy", "sourceExecutionProfilePolicy", "tclDisplayPrecisionPolicy",
              "fileExclusionPolicy", "expressionSamplingPolicy")
    metadata = {field: deepcopy(report[field]) for field in fields}
    metadata.update(feature_counts(records))
    metadata.update(sourceFiles={file["file"]: file["sha256"] for file in report["files"]},
        extraction={"path": "extraction.json.gz", "sha256": digest(compressed),
                    "uncompressedSha256": digest(payload), "recordedCases": len(records)})
    write(directory, [(record["upstream"]["file"], "upstream", [record]) for record in records],
          corpus_version=version, metadata=metadata)
    (directory / "extraction.json.gz").write_bytes(compressed)


def test_retained_routes_survive_future_policy_changes(acquisition: tuple[dict[str, Json], list[dict[str, Json]]],
                                                     tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A self-contained historical policy loads and freshly replays after present-day routes change."""
    import conformance.upstream_profiles as current
    report, records = acquisition
    monkeypatch.setattr(current, "FOREIGN_KEY_PATTERNS", ())
    monkeypatch.setattr(current, "CLOCK_PATTERNS", ())
    monkeypatch.setattr(current, "CLOCK_UNIX_MILLISECONDS", 1800000000000)
    directory = tmp_path / "v5"
    store(directory, report, records)
    _manifest, loaded = load(directory)
    assert loaded == records
    native_replay(loaded)
    verify(report, list(reversed(loaded)))


def test_source_owned_precision_remains_bound_to_its_policy(
        acquisition: tuple[dict[str, Json], list[dict[str, Json]]], tmp_path: Path) -> None:
    """New exact REAL evidence loads at precision 15 without weakening historical policy v1."""
    report, records = acquisition
    report["tclDisplayPrecisionPolicy"]["version"] = 2
    report["files"][0]["instances"][0]["tclResultPrecision"]["values"] = [15]
    records[0]["upstream"]["tclResultPrecision"]["values"] = [15]
    directory = tmp_path / "source-precision"
    store(directory, report, records)
    native_replay(load(directory)[1])
    report["tclDisplayPrecisionPolicy"]["version"] = 1
    with pytest.raises(ValueError, match="precision evidence differs"):
        verify(report, records)


@pytest.mark.parametrize("damage", ["identity", "source", "labels", "scope", "profile", "setup-clock", "event-clock",
    "file-clock", "precision", "precision-count", "record-precision", "file-precision", "completion", "occurrence",
    "accepted-instance", "duplicate-instance", "excluded-instance", "route", "route-version", "policy-version",
    "precision-version", "engine", "catalog", "count", "precision-link", "accepted-refusal", "missing-record",
    "acquisition-version", "reason-count", "nullvalue-missing", "nullvalue-unobserved", "nullvalue-count",
    "nullvalue-link"])
def test_load_rejects_unbound_accepted_evidence(acquisition: tuple[dict[str, Json], list[dict[str, Json]]],
                                              tmp_path: Path, damage: str) -> None:
    """Rehashed cases remain invalid when their retained source, profile or accepted instance disagrees."""
    report, records = acquisition
    record, file = records[1], report["files"][1]
    instance = file["instances"][0]
    if damage == "identity": record["upstream"]["id"] = "another-assertion"
    elif damage == "source": record["upstream"]["sourceSha256"] = "0" * 64
    elif damage == "labels": record["features"] = ["unobserved-feature"]
    elif damage == "scope": record["featureMetadataScope"] = "case"
    elif damage == "profile": record["profile"]["foreignKeys"] = False
    elif damage == "setup-clock": record["setupClockUnixMilliseconds"] += 1000
    elif damage == "event-clock": record["trace"][0]["clockUnixMilliseconds"] += 1000
    elif damage == "file-clock": file["clockUnixMilliseconds"] += 1000
    elif damage == "precision": instance["tclResultPrecision"]["values"] = [15]
    elif damage == "precision-count": instance["tclResultPrecision"]["successfulCalls"] = True
    elif damage == "record-precision": record["upstream"]["tclDisplayPrecision"] = False
    elif damage == "file-precision": file["tclDisplayPrecision"]["established"] = False
    elif damage == "completion": file["runtimeComplete"] = False
    elif damage == "occurrence": instance["occurrence"] = True
    elif damage == "accepted-instance": instance["id"] = "another-assertion"
    elif damage == "duplicate-instance": report["files"].append(deepcopy(file)); report["sourceCatalog"].append(deepcopy(report["sourceCatalog"][1]))
    elif damage == "excluded-instance": report["files"][2]["instances"] = []
    elif damage == "route": file["executionProfile"] = deepcopy(report["files"][0]["executionProfile"])
    elif damage == "route-version": report["sourceExecutionProfilePolicy"]["profiles"][0]["version"] = True
    elif damage == "policy-version": report["sourceExecutionProfilePolicy"]["version"] = 2
    elif damage == "precision-version": report["tclDisplayPrecisionPolicy"]["version"] = True
    elif damage == "engine": report["sourceId"] = "another engine"
    elif damage == "catalog": report["sourceCatalog"][1]["features"] = ["different-source-label"]
    elif damage == "count": file["recorded"] = True
    elif damage == "precision-link": instance["tclResultPrecision"]["successfulCalls"] = 2
    elif damage == "nullvalue-missing": instance.pop("tclNullvalueEvidence")
    elif damage == "nullvalue-unobserved": instance["tclNullvalueEvidence"]["values"] = [None]
    elif damage == "nullvalue-count": instance["tclNullvalueEvidence"]["successfulCalls"] = True
    elif damage == "nullvalue-link": record["upstream"]["tclNullvalueEvidence"]["values"] = ["NULL"]
    elif damage == "accepted-refusal":
        instance.update(result="unsupported prefix", exclusions=["unsupported prefix"])
        file.update(recorded=0, reasons={"unsupported prefix": 1})
    elif damage == "missing-record": records.pop(); report["recordedCases"] = 1
    elif damage == "acquisition-version": report["corpusVersion"] = True
    elif damage == "reason-count": file["reasons"]["recorded"] = True
    directory = tmp_path / "damaged"
    store(directory, report, records)
    with pytest.raises(ValueError):
        load(directory)


def test_v4_retains_historical_loader_contract(acquisition: tuple[dict[str, Json], list[dict[str, Json]]], tmp_path: Path) -> None:
    """Old extraction without v5 precision/profile fields remains readable without retrospective routing."""
    report, records = acquisition
    directory = tmp_path / "v4"
    for record in records:
        record["upstream"].pop("tclDisplayPrecision")
        record["upstream"].pop("tclResultPrecision")
        record["upstream"].pop("tclNullvalueEvidence")
    store(directory, report, records, version=4)
    _manifest, loaded = load(directory)
    assert loaded == records
