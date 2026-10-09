"""Replay an immutable native corpus through the current frontend and compiled model."""

import argparse
from collections import Counter, defaultdict
from concurrent.futures import Executor
import gzip
import hashlib
import json
from pathlib import Path

from conformance.case_format import Json
from conformance.model_check import compiled_many
from conformance.native_record import record_sql
from conformance.native_bindings import decode_rows
from conformance.native_replay import prepare, without_trailing_queries
from conformance.execution_profile import ExecutionProfile, recorded_profile, validate_manifest_profiles
from conformance.native_storage import expanded_record
from conformance.native_call_recording import replay_arguments, validate_recording
from conformance.record_parser import NO_PARSER_REASON, runtime_library


def load(directory: Path, *, executor: Executor | None = None) -> tuple[dict[str, Json], list[dict[str, Json]]]:
    """Bind every case to exact content, serially by default or with a caller-owned shard executor."""
    manifest = json.loads((directory / "manifest.json").read_text())
    if isinstance(manifest, dict) and ("shards" in manifest or "shardStorageVersion" in manifest):
        from conformance.corpus_shards import load as load_shards
        return manifest, load_shards(directory, manifest, executor=executor)
    payload = gzip.decompress((directory / "cases.jsonl.gz").read_bytes())
    if hashlib.sha256(payload).hexdigest() != manifest["casesSha256"]:
        raise ValueError("Corpus digest mismatch")
    records = [expanded_record(json.loads(line)) for line in payload.splitlines()]
    for record in records:
        validate_recording(record)
    if len(records) != manifest["recordedCases"] or type(manifest["corpusVersion"]) is not int or manifest["corpusVersion"] < 1:
        raise ValueError("Corpus version/count mismatch")
    validate_manifest_profiles(manifest, records)
    if "files" in manifest and "extractorSha256" in manifest:
        from conformance.upstream_binding_policy import validate_capture_bindings
        validate_capture_bindings(manifest, records)
    return manifest, records


def replay(records: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
    """Count frontend exclusions separately while using Lean as the only agreement oracle."""
    cases: list[dict[str, Json]] = []
    positions: list[int] = []
    answers: list[dict[str, Json]] = []
    library = runtime_library(runtime)
    for position, record in enumerate(records):
        case, answer = prepare(record, library)
        answers.append(answer)
        if case is not None:
            positions.append(position)
            cases.append(case)
    for position, answer in zip(positions, compiled_many(cases, runtime) if cases else [], strict=True):
        answers[position] = answer
    query_counts: Counter[str] = Counter()
    for record, answer in zip(records, answers, strict=True):
        if answer["verdict"] != "MODEL_UNSUPPORTED" or answer.get("reason") == NO_PARSER_REASON:
            continue
        projection = without_trailing_queries(record, library)
        if projection is None:
            query_counts["OTHER_UNSUPPORTED"] += 1
            continue
        case, prefix_answer = prepare(projection, library)
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
            "noParserForDialect": sum(answer.get("reason") == NO_PARSER_REASON for answer in answers),
            "byArea": {key: dict(value) for key, value in sorted(areas.items())},
            "byRequirement": {key: dict(value) for key, value in sorted(requirements.items())}, "cases": details}


def native_replay(records: list[dict[str, Json]], *, profile: ExecutionProfile | None = None,
                  temporary_root: Path | None = None, fixture_paths: list[Path] | None = None) -> None:
    """Verify frozen observations without rewriting evidence, optionally auditing explicit file storage."""
    for record in records:
        recording = replay_arguments(record)
        selected_profile = recorded_profile(record) if record["nativeVersion"] == 4 else None
        if profile is not None and selected_profile != profile:
            raise ValueError("Native replay execution profile differs")
        outputs = record["nativeVersion"] in (3, 4)
        parameters = decode_rows([event["parameters"] for event in record["trace"]]) if outputs else None
        clock_values = [event["clockUnixMilliseconds"] for event in record["trace"]] if selected_profile and selected_profile.clock == "unix-milliseconds-v1" else None
        fresh = record_sql(record["setupCommands"], record["migrationSql"], name=record["name"],
            outputs=outputs, parameters=parameters, profile=selected_profile,
            setup_clock=record.get("setupClockUnixMilliseconds"), clock_values=clock_values,
            temporary_root=temporary_root, fixture_paths=fixture_paths, **recording)
        if (fresh["initial"], fresh["trace"]) != (record["initial"], record["trace"]):
            raise ValueError(f"Native replay changed: {record['name']}")
        if recording and fresh["setupBindings"] != record["setupBindings"]:
            raise ValueError(f"Native replay setup bindings changed: {record['name']}")


def main() -> None:
    """Write progress for an explicitly selected corpus version and current runtime."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--native-check", action="store_true")
    parser.add_argument("--temporary-root", type=Path, help="Existing writable directory for native file fixtures")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.native_check and args.temporary_root is None:
        parser.error("--native-check requires --temporary-root PATH; select an existing writable directory")
    if args.temporary_root is not None and not args.native_check:
        parser.error("--temporary-root requires --native-check")
    if args.output.resolve().is_relative_to(args.directory.resolve()):
        parser.error("Replay report must be outside the selected corpus; choose another --output path")
    manifest, records = load(args.directory)
    native: dict[str, Json] = {}
    if args.native_check:
        from conformance.native_replay_report import report
        try:
            native = report(args.directory, records, args.runtime_root, args.temporary_root)
        except (OSError, ValueError) as error:
            parser.error(str(error))
    result = {"corpusVersion": manifest["corpusVersion"], "casesSha256": manifest["casesSha256"],
              "denominator": len(records), **native, **replay(records, args.runtime_root.resolve())}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["counts"]))


if __name__ == "__main__":
    main()
