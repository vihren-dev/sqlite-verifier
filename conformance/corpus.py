"""Replay an immutable native corpus through the current frontend and compiled model."""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.model_check import compiled_many
from conformance.native_record import record_sql
from conformance.native_replay import decode_rows, prepare, without_trailing_queries


def load(directory: Path) -> tuple[dict[str, Json], list[dict[str, Json]]]:
    """Bind the case denominator to a version and exact uncompressed content digest."""
    manifest = json.loads((directory / "manifest.json").read_text())
    payload = gzip.decompress((directory / "cases.jsonl.gz").read_bytes())
    if hashlib.sha256(payload).hexdigest() != manifest["casesSha256"]:
        raise ValueError("Corpus digest mismatch")
    records = [json.loads(line) for line in payload.splitlines()]
    if len(records) != manifest["recordedCases"] or type(manifest["corpusVersion"]) is not int or manifest["corpusVersion"] < 1:
        raise ValueError("Corpus version/count mismatch")
    return manifest, records


def replay(records: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
    """Count frontend exclusions separately while using Lean as the only agreement oracle."""
    cases: list[dict[str, Json]] = []
    positions: list[int] = []
    answers: list[dict[str, Json]] = []
    for position, record in enumerate(records):
        case, answer = prepare(record, runtime / "build/sqlite-parser")
        answers.append(answer)
        if case is not None:
            positions.append(position)
            cases.append(case)
    for position, answer in zip(positions, compiled_many(cases, runtime) if cases else [], strict=True):
        answers[position] = answer
    query_counts: Counter[str] = Counter()
    for record, answer in zip(records, answers, strict=True):
        if answer["verdict"] != "MODEL_UNSUPPORTED":
            continue
        projection = without_trailing_queries(record, runtime / "build/sqlite-parser")
        if projection is None:
            query_counts["OTHER_UNSUPPORTED"] += 1
            continue
        case, prefix_answer = prepare(projection, runtime / "build/sqlite-parser")
        if case is not None:
            prefix_answer = compiled_many([case], runtime)[0]
        category = "PREFIX_" + prefix_answer["verdict"]
        if prefix_answer["verdict"] == "AGREE":
            category = "BLOCKED_ONLY_BY_QUERIES" if projection["trace"] else "QUERY_ONLY_CASE"
        query_counts[category] += 1
        answer["queryDiagnostic"] = {"category": category, "prefix": prefix_answer,
            "migrationStatements": len(projection["trace"]), "trailingObservations": len(record["trace"]) - len(projection["trace"])}
    areas: dict[str, Counter[str]] = defaultdict(Counter)
    requirements: dict[str, Counter[str]] = defaultdict(Counter)
    details: list[Json] = []
    for record, answer in zip(records, answers, strict=True):
        verdict = answer["verdict"]
        areas[record.get("upstream", {}).get("file", "authored")][verdict] += 1
        for requirement in record["requirements"] or ["UNTAGGED"]:
            requirements[requirement][verdict] += 1
        details.append({"name": record["name"], **answer})
    return {"queryDiagnostics": dict(query_counts), "counts": dict(Counter(answer["verdict"] for answer in answers)),
            "byArea": {key: dict(value) for key, value in sorted(areas.items())},
            "byRequirement": {key: dict(value) for key, value in sorted(requirements.items())}, "cases": details}


def native_replay(records: list[dict[str, Json]]) -> None:
    """Verify all frozen observations against fresh connections without rewriting evidence."""
    for record in records:
        outputs = record["nativeVersion"] == 3
        parameters = decode_rows([event["parameters"] for event in record["trace"]]) if outputs else None
        fresh = record_sql(record["setupCommands"], record["migrationSql"], name=record["name"],
                           outputs=outputs, parameters=parameters)
        if (fresh["initial"], fresh["trace"]) != (record["initial"], record["trace"]):
            raise ValueError(f"Native replay changed: {record['name']}")


def main() -> None:
    """Write progress for an explicitly selected corpus version and current runtime."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--native-check", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest, records = load(args.directory)
    if args.native_check:
        native_replay(records)
    result = {"corpusVersion": manifest["corpusVersion"], "casesSha256": manifest["casesSha256"],
              "denominator": len(records), **replay(records, args.runtime_root.resolve())}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["counts"]))


if __name__ == "__main__":
    main()
