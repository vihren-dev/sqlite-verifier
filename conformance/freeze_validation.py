"""Refuse incomplete acquisition and unbound Tcl/native triage before a C6 freeze."""

import hashlib
from pathlib import Path
import re

from conformance.case_format import Json
from conformance.corpus_shards import natural, source_path
from conformance.corpus_acquisition import verify
from conformance.upstream_profiles import source_profile_policy, tcl_precision_policy
from conformance.upstream_binding_policy import binding_policy
from conformance.native_connection import SOURCE_ID
from conformance.native_storage import serialized
from conformance.upstream_catalog import CATALOG_VERSION, catalog_patterns, exclusion_policy, family_policy, source_catalog
from conformance.upstream_sampling import EXPRESSION_COHORTS, sampling_policy, select_candidates

ARCHIVE_SHA256 = "5330719b8b80bf563991ff7a373052943f5357aae76cd1f3367eab845d3a75b7"
EXTRACTOR_FILES = frozenset(path.name for pattern in ("*.py", "upstream*.tcl")
                            for path in Path(__file__).parent.glob(pattern))


def digest(payload: bytes) -> str:
    """Use the same SHA-256 identity for source files, retained evidence and transport."""
    return hashlib.sha256(payload).hexdigest()


def extractor_hashes(directory: Path) -> dict[str, str]:
    """Bind the complete harness and Tcl helper bytes used during acquisition."""
    return {name: digest(source_path(directory, name).read_bytes()) for name in sorted(EXTRACTOR_FILES)}


def mismatch(reason: str) -> bool:
    """Identify every fidelity comparison refusal, including already named environment causes."""
    return "differ" in reason and "from Tcl execution" in reason


def acquisition(report: dict[str, Json], records: list[dict[str, Json]], upstream: Path,
                root: Path) -> set[tuple[str, str, int]]:
    """Bind exact sources, fixed sampling, completed candidates and the accepted membership."""
    if (type(report.get("corpusVersion")) is not int or report["corpusVersion"] != 2
            or natural(report.get("recordedCases")) != len(records)
            or type(report.get("sourceCatalogVersion")) is not int or report["sourceCatalogVersion"] != CATALOG_VERSION
            or report.get("sourceCatalog") != source_catalog()
            or serialized(report.get("sourceFamilyPolicy")) != serialized(family_policy())
            or serialized(report.get("sourceExecutionProfilePolicy")) != serialized(source_profile_policy())
            or serialized(report.get("tclDisplayPrecisionPolicy")) != serialized(tcl_precision_policy())
            or serialized(report.get("tclBindingPolicy")) != serialized(binding_policy())
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
    verify(report, records)
    refusals: set[tuple[str, str, int]] = set()
    for file, declaration in zip(files, source_catalog(), strict=True):
        filename = file["file"]
        if (file.get("features") != declaration["features"]
                or file.get("fileExclusions") != declaration["fileExclusions"]
                or digest(source_path(upstream / "test", filename).read_bytes()) != file.get("sha256")):
            raise ValueError("Acquisition source hash or labels differ")
        if declaration["fileExclusions"]:
            continue
        instances = file["instances"]
        for instance in instances:
            if any(mismatch(reason) for reason in instance["exclusions"]):
                refusals.add((filename, instance["id"], instance["occurrence"]))
        sampled, choices = select_candidates(filename, instances, EXPRESSION_COHORTS)
        if (file.get("expressionSampling") != choices
                or any((sampled.get(index) in instance["exclusions"]) != (index in sampled)
                       for index, instance in enumerate(instances))):
            raise ValueError("Acquisition sampling or result accounting differs")
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
