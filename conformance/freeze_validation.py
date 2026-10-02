"""Refuse incomplete acquisition and unbound Tcl/native triage before a C6 freeze."""

from collections import Counter
import hashlib
from pathlib import Path
import re

from conformance.case_format import Json
from conformance.corpus_shards import natural, source_path
from conformance.native_connection import SOURCE_ID
from conformance.native_storage import serialized
from conformance.upstream_catalog import catalog_patterns, exclusion_policy, source_catalog
from conformance.upstream_sampling import EXPRESSION_COHORTS, sampling_policy, select_candidates

ARCHIVE_SHA256 = "5330719b8b80bf563991ff7a373052943f5357aae76cd1f3367eab845d3a75b7"
EXTRACTOR_FILES = {"upstream_pilot.py", "upstream_assertions.py", "upstream_helpers.py", "upstream_proxy.tcl",
                   "upstream_fidelity.py", "upstream_selection.py", "upstream_catalog.py", "upstream_sampling.py",
                   "native_record.py", "native_storage.py"}


def digest(payload: bytes) -> str:
    """Use the same SHA-256 identity for source files, retained evidence and transport."""
    return hashlib.sha256(payload).hexdigest()


def mismatch(reason: str) -> bool:
    """Identify every fidelity comparison refusal, including already named environment causes."""
    return "differ" in reason and "from Tcl execution" in reason


def acquisition(report: dict[str, Json], records: list[dict[str, Json]], upstream: Path,
                root: Path) -> set[tuple[str, str, int]]:
    """Bind exact sources, fixed sampling, completed candidates and the accepted membership."""
    if (type(report.get("corpusVersion")) is not int or report["corpusVersion"] != 1
            or natural(report.get("recordedCases")) != len(records)
            or type(report.get("sourceCatalogVersion")) is not int or report["sourceCatalogVersion"] != 1
            or report.get("sourceCatalog") != source_catalog()
            or report.get("fileExclusionPolicy") != exclusion_policy()
            or report.get("expressionSamplingPolicy") != sampling_policy(EXPRESSION_COHORTS)
            or report.get("patterns") != list(catalog_patterns())
            or "perFileLimit" not in report or report["perFileLimit"] is not None
            or report.get("sourceRelease") != "3.51.0" or report.get("sourceId") != SOURCE_ID
            or report.get("sourceArchiveSha256") != ARCHIVE_SHA256):
        raise ValueError("Acquisition catalog, policy, pin or uncapped limit differs")
    hashes = report.get("extractorSha256")
    if not isinstance(hashes, dict) or set(hashes) != EXTRACTOR_FILES:
        raise ValueError("Missing acquisition extractor hashes")
    for name, expected in hashes.items():
        if digest(source_path(root / "conformance", name).read_bytes()) != expected:
            raise ValueError("Acquisition extractor changed")
    files = report.get("files")
    if (not isinstance(files, list) or len(files) != len(catalog_patterns())
            or any(not isinstance(file, dict) for file in files)
            or [file.get("file") for file in files] != list(catalog_patterns())):
        raise ValueError("Acquisition source files are incomplete or duplicated")
    accepted: dict[tuple[str, str, int], dict[str, Json]] = {}
    refusals: set[tuple[str, str, int]] = set()
    for file, declaration in zip(files, source_catalog(), strict=True):
        filename = file["file"]
        if (file.get("features") != declaration["features"]
                or file.get("fileExclusions") != declaration["fileExclusions"]
                or digest(source_path(upstream / "test", filename).read_bytes()) != file.get("sha256")):
            raise ValueError("Acquisition source hash or labels differ")
        if file.get("timedOut") or file.get("incomplete") or file.get("runtimeComplete") is False:
            raise ValueError("Acquisition runtime is incomplete or timed out")
        if declaration["fileExclusions"]:
            if (file.get("excludedFile") != "; ".join(declaration["fileExclusions"])
                    or {"instances", "runtimeAssertions", "runtimeExit", "runtimeComplete", "recorded"} & file.keys()):
                raise ValueError("Acquisition file exclusion differs")
            continue
        if ("excludedFile" in file or type(file.get("runtimeExit")) is not int
                or file.get("runtimeComplete") is not True):
            raise ValueError("Acquisition runtime is incomplete")
        instances = file.get("instances")
        if not isinstance(instances, list) or natural(file.get("runtimeAssertions")) != len(instances):
            raise ValueError("Acquisition runtime count differs")
        for occurrence, instance in enumerate(instances):
            if (not isinstance(instance, dict) or not isinstance(instance.get("id"), str)
                    or not instance["id"] or natural(instance.get("occurrence")) != occurrence
                    or not isinstance(instance.get("exclusions"), list)
                    or any(not isinstance(reason, str) or not reason for reason in instance["exclusions"])
                    or len(set(instance["exclusions"])) != len(instance["exclusions"])
                    or instance.get("result") != ("; ".join(instance["exclusions"]) or "recorded")):
                raise ValueError("Acquisition candidate accounting differs")
            identity = (filename, instance["id"], occurrence)
            if instance["result"] == "recorded":
                accepted[identity] = file
            if any(mismatch(reason) for reason in instance["exclusions"]):
                refusals.add(identity)
        sampled, choices = select_candidates(filename, instances, EXPRESSION_COHORTS)
        if (file.get("expressionSampling") != choices
                or file.get("reasons") != dict(Counter(instance["result"] for instance in instances))
                or natural(file.get("recorded")) != sum(instance["result"] == "recorded" for instance in instances)
                or any((sampled.get(index) in instance["exclusions"]) != (index in sampled)
                       for index, instance in enumerate(instances))):
            raise ValueError("Acquisition sampling or result accounting differs")
    observed: set[tuple[str, str, int]] = set()
    for record in records:
        provenance = record.get("upstream")
        if (not isinstance(provenance, dict) or any(
                not isinstance(provenance.get(key), str) or not provenance[key] for key in ("file", "id"))):
            raise ValueError("Missing upstream case provenance")
        identity = (provenance.get("file"), provenance.get("id"), natural(provenance.get("occurrence")))
        file = accepted.get(identity)
        if (file is None or identity in observed or type(record.get("nativeVersion")) is not int
                or record["nativeVersion"] != 4 or record.get("part") != "upstream"
                or record.get("features") != file["features"] or record.get("featureMetadataScope") != "source-file"
                or provenance.get("sourceSha256") != file["sha256"]):
            raise ValueError("Acquisition accepted membership or profile format differs")
        observed.add(identity)
    if observed != set(accepted):
        raise ValueError("Acquisition accepted membership differs")
    return refusals


def triage(value: Json, expected: set[tuple[str, str, int]], extraction_digest: str,
           directory: Path) -> dict[str, bytes]:
    """Require one named cause and verified retained evidence for every mismatch identity."""
    if value is None and not expected:
        return {}
    if (not isinstance(value, dict) or set(value) != {"ledgerVersion", "extractionSha256", "entries"}
            or type(value["ledgerVersion"]) is not int or value["ledgerVersion"] != 1
            or value["extractionSha256"] != extraction_digest or not isinstance(value["entries"], list)):
        raise ValueError("Missing or invalid fidelity ledger binding")
    seen: set[tuple[str, str, int]] = set()
    evidence: dict[str, bytes] = {}
    for entry in value["entries"]:
        if (not isinstance(entry, dict) or set(entry) != {"file", "id", "occurrence", "cause", "evidence"}
                or any(not isinstance(entry[key], str) or not entry[key].strip() for key in ("file", "id", "cause"))
                or not isinstance(entry["evidence"], list) or not entry["evidence"]):
            raise ValueError("Invalid fidelity ledger cause or evidence")
        identity = (entry["file"], entry["id"], natural(entry["occurrence"]))
        if identity in seen or identity not in expected:
            raise ValueError("Duplicate or unrelated fidelity ledger identity")
        seen.add(identity)
        for reference in entry["evidence"]:
            if (not isinstance(reference, dict) or set(reference) != {"path", "sha256"}
                    or not isinstance(reference["sha256"], str)
                    or not re.fullmatch(r"[0-9a-f]{64}", reference["sha256"])):
                raise ValueError("Invalid fidelity evidence reference")
            path = source_path(directory, reference["path"])
            payload = path.read_bytes()
            if not payload or digest(payload) != reference["sha256"]:
                raise ValueError("Fidelity evidence digest differs")
            evidence[reference["path"]] = payload
    if seen != expected:
        raise ValueError("Untriaged fidelity mismatch identities")
    return evidence
