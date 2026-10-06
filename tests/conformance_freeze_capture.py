"""Build complete acquisition fixtures while keeping freeze acceptance checks separate."""

from copy import deepcopy
import gzip
from pathlib import Path

import pytest

from conformance.authored_cases import AuthoredCase
from conformance.case_format import Json
import conformance.freeze_corpus as finalizer
from conformance.freeze_validation import ARCHIVE_SHA256, EXTRACTOR_FILES, digest
from conformance.freeze_profiles import PRECISION_POLICY
from conformance.upstream_profiles import catalog_profiles, profile_for_source, source_profile_policy
from conformance.upstream_binding_policy import binding_policy
from conformance.native_connection import SOURCE_ID
from conformance.native_record import record_sql
from conformance.native_storage import serialized, shared_record
from conformance.upstream_catalog import CATALOG_VERSION, catalog_patterns, exclusion_policy, family_policy, source_catalog
from conformance.upstream_sampling import EXPRESSION_COHORTS, sampling_policy, select_candidates

ROOT = Path(__file__).resolve().parents[1]

def save(directory: Path, report: dict[str, Json], record: dict[str, Json]) -> None:
    """Rebind the input transport when testing selection rather than a stale outer digest."""
    payload = serialized(record) + b"\n"
    report["casesSha256"] = digest(payload)
    (directory / "cases.jsonl.gz").write_bytes(gzip.compress(payload, mtime=0))
    (directory / "manifest.json").write_bytes(serialized(report))

@pytest.fixture
def capture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path, dict[str, Json], dict[str, Json]]:
    """A synthetic complete 171-source scan uses real typed evidence and minimal authored stand-ins."""
    directory, upstream = tmp_path / "capture", tmp_path / "upstream"
    directory.mkdir()
    (upstream / "test").mkdir(parents=True)
    profiles = catalog_profiles()
    profile, clock = profile_for_source("expr.test", profiles)
    sql = "SELECT $probe AS value;"
    call: dict[str, Json] = {"sql": sql, "helper": "eval", "code": 0, "results": ["\x00\xff"],
        "precision": 0, "nullValue": "", "bindings": {"$probe": {"blob": {"bytes": [0, 255]}}},
        "objects": {"$probe": {"type": "bytearray", "hasString": False}}}
    record = record_sql([], sql, name="probe", outputs=True,
        tcl_calls={"version": 1, "setup": [], "assertion": [call]},
        profile=profile, setup_clock=clock, clock_values=clock)
    calls_digest = digest(serialized(record["sourceCalls"]))
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
            source_profile, source_clock = profile_for_source(declaration["file"], profiles)
            file.update(executionProfile={"name": source_profile.name, "version": 1},
                clockUnixMilliseconds=source_clock, tclDisplayPrecision={"original": 15, "established": 0, "requested": 0})
            instances = [{"id": "probe", "occurrence": 0, "result": "recorded", "exclusions": [],
                          "tclCallsSha256": calls_digest,
                          "tclResultPrecision": {"values": [0], "successfulCalls": 1}, "tclNullvalueEvidence": {"values": [""], "successfulCalls": 1}}]
            instances = instances if declaration["file"] == "expr.test" else []
            file.update(runtimeExit=0, runtimeComplete=True, runtimeAssertions=len(instances), recorded=len(instances),
                reasons={"recorded": 1} if instances else {}, instances=instances,
                expressionSampling=select_candidates(declaration["file"], instances, EXPRESSION_COHORTS)[1])
        files.append(file)
    record["upstream"] = {"file": "expr.test", "id": "probe", "occurrence": 0,
                          "tclCallsSha256": calls_digest,
                          "tclResultPrecision": {"values": [0], "successfulCalls": 1}, "tclNullvalueEvidence": {"values": [""], "successfulCalls": 1},
                          "tclDisplayPrecision": 0, "sourceSha256": next(file["sha256"] for file in files if file["file"] == "expr.test")}
    report: dict[str, Json] = {"corpusVersion": 2, "recordedCases": 1, "sourceId": SOURCE_ID,
        "sourceRelease": "3.51.0", "sourceArchiveSha256": ARCHIVE_SHA256, "perFileLimit": None,
        "patterns": list(catalog_patterns()), "sourceCatalogVersion": CATALOG_VERSION, "sourceCatalog": source_catalog(), "sourceFamilyPolicy": family_policy(),
        "sourceExecutionProfilePolicy": source_profile_policy(), "tclDisplayPrecisionPolicy": PRECISION_POLICY,
        "tclBindingPolicy": binding_policy(),
        "fileExclusionPolicy": exclusion_policy(), "expressionSamplingPolicy": sampling_policy(EXPRESSION_COHORTS),
        "executionProfiles": [item.to_wire() for item in profiles.values()], "files": files,
        "extractorSha256": {name: digest((ROOT / "conformance" / name).read_bytes()) for name in EXTRACTOR_FILES}}
    save(directory, report, shared_record(record))
    def authored(cases: list[AuthoredCase] | None = None) -> list[dict[str, Json]]:
        """Keep fresh native round trips while avoiding repeated acquisition of the full tested catalog."""
        parts = ["boundary-interaction", "requirement"] if cases is None else ["boundary-interaction"]
        name = "review-case" if cases and cases[0].name == "deferred-foreign-key-repaired-commit" else "issue-case"
        records = [{**deepcopy(record), "name": f"authored-{index}" if cases is None else name, "part": part,
                    "features": ["typed-parameters"], "featureMetadataScope": "case"} for index, part in enumerate(parts)]
        for item in records:
            del item["upstream"]
        return records
    monkeypatch.setattr(finalizer, "authored_records", authored)
    return directory, upstream, report, record

