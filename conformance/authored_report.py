"""Retain fresh authored evidence and compare requirement scenarios before a freeze."""

import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path

from conformance.authored_cases import records
from conformance.case_format import Json
from conformance.corpus import load, native_replay, replay
from conformance.corpus_evidence import feature_counts
from conformance.native_storage import serialized, shared_record
from conformance.requirement_coverage import comparison


def acquire(before: Path, requirements: Path, runtime: Path) -> tuple[dict[str, Json], bytes]:
    """Verify fresh records and retain the inventory denominator independently of model support."""
    manifest, previous = load(before)
    authored = records()
    names = {record["name"] for record in authored}
    if len(names) != len(authored):
        raise ValueError("Authored case names are not unique")
    replaced = [record for record in previous if record["name"] in names]
    by_name = {record["name"]: record for record in authored}
    if any((old["setupSql"], old["migrationSql"]) !=
           (by_name[old["name"]]["setupSql"], by_name[old["name"]]["migrationSql"])
           for old in replaced):
        raise ValueError("A retained requirement scenario changed its SQL")
    after = [record for record in previous if record["name"] not in names] + authored
    native_replay(authored)
    model = replay(authored, runtime)
    if model["counts"].get("HARNESS_ERROR", 0) or model["counts"].get("DISAGREE", 0):
        raise ValueError("Authored evidence failed model classification")
    stored = [shared_record(record) for record in authored]
    payload = b"".join(serialized(record) + b"\n" for record in stored)
    inventory = json.loads(requirements.read_text())
    sources = sorted(Path(__file__).parent.glob("*.py"))
    profiles = {serialized(record["profile"]): record["profile"] for record in authored}
    report: dict[str, Json] = {
        "reportVersion": 1,
        "baseline": {"corpusVersion": manifest["corpusVersion"],
                     "casesSha256": manifest["casesSha256"], "recordedCases": len(previous)},
        "requirementsSha256": hashlib.sha256(requirements.read_bytes()).hexdigest(),
        "sourceHashes": {str(path.relative_to(Path(__file__).resolve().parents[1])):
                        hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
        "authoredEvidence": {"casesSha256": hashlib.sha256(payload).hexdigest(),
                             "recordedCases": len(authored), "nativeVersion": 4,
                             "snapshotStorageVersion": 1, "nativeReplayPassed": True,
                             "uncompressedBytes": len(payload),
                             "maximumExpandedCaseBytes": max(len(serialized(record)) for record in authored),
                             "executionProfiles": list(profiles.values())},
        "replacementCases": len(replaced), "newCases": len(authored) - len(replaced),
        "coverage": comparison(previous, after, inventory),
        "byPart": dict(Counter(record["part"] for record in authored)),
        **feature_counts(authored),
        "modelClassification": model,
        "limitation": "Scenario labels do not measure SQL execution coverage or prove entire requirements. The after membership replaces legacy authored evidence and adds neutral cases; C6 determines the final upstream membership. JSON has feature metadata without requirement credit. Model support has not been extended.",
    }
    return report, payload


def main() -> None:
    """Write digest-bound C5 evidence without modifying any frozen corpus."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, default=Path("conformance/corpus-v3"))
    parser.add_argument("--requirements", type=Path, default=Path("conformance/requirements-3.51.0.json"))
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output-prefix", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_prefix.with_suffix(".json")
    evidence = output.with_name(output.stem + "-records.jsonl.gz")
    if output.exists() or evidence.exists():
        raise ValueError("Authored report output already exists; choose a new output prefix")
    report, payload = acquire(args.before, args.requirements, args.runtime_root.resolve())
    report["authoredEvidence"]["file"] = evidence.name
    output.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_bytes(gzip.compress(payload, mtime=0))
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"cases": report["authoredEvidence"]["recordedCases"],
                      "beforeRowsWithCases": report["coverage"]["beforeRowsWithCases"],
                      "afterRowsWithCases": report["coverage"]["afterRowsWithCases"]}))


if __name__ == "__main__":
    main()
