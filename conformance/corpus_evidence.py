"""Verify retained optional acquisition and fidelity proofs before ordinary corpus replay."""

import gzip
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.corpus_shards import natural, source_path
from conformance.freeze_validation import digest, mismatch, triage


def document(directory: Path, binding: dict[str, Json]) -> tuple[dict[str, Json], bytes, Path]:
    """Check both compressed transport and original JSON identity before reading evidence fields."""
    path = source_path(directory, binding.get("path"))
    compressed = path.read_bytes()
    if digest(compressed) != binding.get("sha256"):
        raise ValueError("Corpus evidence compressed digest differs")
    try:
        payload = gzip.decompress(compressed)
    except (OSError, EOFError) as error:
        raise ValueError("Invalid compressed corpus evidence") from error
    if digest(payload) != binding.get("uncompressedSha256"):
        raise ValueError("Corpus evidence uncompressed digest differs")
    value = json.loads(payload)
    if not isinstance(value, dict):
        raise ValueError("Invalid corpus evidence document")
    return value, payload, path


def refusals(report: dict[str, Json]) -> set[tuple[str, str, int]]:
    """Retain every comparison-failure identity even when its diagnostic already names a cause."""
    files = report.get("files")
    if not isinstance(files, list):
        raise ValueError("Invalid corpus extraction sources")
    result: set[tuple[str, str, int]] = set()
    for file in files:
        if not isinstance(file, dict) or not isinstance(file.get("file"), str):
            raise ValueError("Invalid corpus extraction source")
        instances = file.get("instances", [])
        if not isinstance(instances, list):
            raise ValueError("Invalid corpus extraction instances")
        for instance in instances:
            if (not isinstance(instance, dict) or not isinstance(instance.get("id"), str)
                    or not isinstance(instance.get("exclusions"), list)
                    or any(not isinstance(reason, str) for reason in instance["exclusions"])):
                raise ValueError("Invalid corpus extraction refusal")
            if any(mismatch(reason) for reason in instance["exclusions"]):
                identity = (file["file"], instance["id"], natural(instance.get("occurrence")))
                if identity in result:
                    raise ValueError("Duplicate corpus extraction refusal")
                result.add(identity)
    return result


def verify(directory: Path, manifest: dict[str, Json], records: list[dict[str, Json]]) -> None:
    """Manifests without C6 proof fields retain their existing legacy or workload loader behavior."""
    if "extraction" not in manifest:
        if "fidelityLedger" in manifest:
            raise ValueError("Corpus fidelity ledger requires bound extraction")
        return
    extraction = manifest["extraction"]
    if not isinstance(extraction, dict) or set(extraction) != {"path", "sha256", "uncompressedSha256", "recordedCases"}:
        raise ValueError("Invalid corpus extraction binding")
    report, payload, _path = document(directory, extraction)
    if (natural(extraction["recordedCases"]) != natural(report.get("recordedCases"))
            or extraction["recordedCases"] != sum(record.get("part") == "upstream" for record in records)):
        raise ValueError("Corpus extraction case count differs")
    fields = ("sourceRelease", "sourceId", "sourceArchiveSha256", "sourceCatalogVersion", "sourceCatalog",
              "fileExclusionPolicy", "expressionSamplingPolicy")
    if any(field not in report or manifest.get(field) != report[field] for field in fields):
        raise ValueError("Corpus extraction policy binding differs")
    expected = refusals(report)
    if manifest.get("sourceFiles") != {file["file"]: file.get("sha256") for file in report["files"]}:
        raise ValueError("Corpus extraction source hashes differ")
    if "fidelityLedger" not in manifest:
        if expected:
            raise ValueError("Missing corpus fidelity ledger")
        return
    binding = manifest["fidelityLedger"]
    if (not isinstance(binding, dict)
            or set(binding) != {"path", "sha256", "uncompressedSha256", "mismatches", "evidence"}
            or not isinstance(binding["evidence"], dict) or natural(binding["mismatches"]) != len(expected)):
        raise ValueError("Invalid corpus fidelity ledger binding")
    ledger, _payload, path = document(directory, binding)
    evidence = triage(ledger, expected, digest(payload), path.parent)
    parent = Path(binding["path"]).parent
    declared = {str(parent / relative): digest(data) for relative, data in evidence.items()}
    if binding["evidence"] != declared:
        raise ValueError("Corpus fidelity evidence declarations differ")
    for relative, expected_digest in binding["evidence"].items():
        if digest(source_path(directory, relative).read_bytes()) != expected_digest:
            raise ValueError("Corpus fidelity evidence digest differs")
