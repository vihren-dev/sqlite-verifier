"""Record and replay external workload evidence without placing it in the core corpus."""

import argparse
from collections import Counter
import json
from pathlib import Path

from conformance.case_format import Json, cell_wire
from conformance.corpus import load, native_replay, replay
from conformance.corpus_shards import write
from conformance.native_record import record_sql
from conformance.query_window import tokens
from conformance.workload_inputs import WorkloadCase, load_inputs


def complete(case: WorkloadCase, evidence: dict[str, Json]) -> None:
    """A first error may terminate execution, but cannot hide inventory entries or bindings."""
    consumed = "".join(event["sql"] for event in evidence["trace"])
    if (not evidence["trace"] or not case.sql.startswith(consumed)
            or any(token.text != ";" for token in tokens(case.sql[len(consumed):]))
            or len(evidence["trace"]) != len(case.parameters)
            or case.clocks is not None and len(evidence["trace"]) != len(case.clocks)):
        raise ValueError(f"Workload inventory contains an unexecuted statement or input: {case.name}")


def record(directory: Path, output: Path) -> dict[str, Json]:
    """Freeze only complete sequences under the inventory's exact measured profile."""
    inputs = load_inputs(directory)
    records: list[dict[str, Json]] = []
    for case in inputs.cases:
        evidence = record_sql(case.setup, case.sql, name=case.name, requirements=case.requirements,
            outputs=True, parameters=case.parameters, profile=inputs.profile,
            setup_clock=inputs.setup_clock, clock_values=case.clocks)
        complete(case, evidence)
        records.append({**evidence, "part": "workload", "features": case.features})
    native_replay(records, profile=inputs.profile)
    return write(output, [("workload", "workload", records)], metadata={
        "workloadInventory": {"formatVersion": 1, "manifest": "workload.json", "sources": inputs.sources},
        "nativeReplayPassed": True})


def bound_records(directory: Path, corpus: Path) -> tuple[dict[str, Json], list[dict[str, Json]]]:
    """Refuse changed inventory, SQL or profile before interpreting frozen observations."""
    inputs = load_inputs(directory)
    manifest, records = load(corpus)
    if manifest.get("workloadInventory") != {"formatVersion": 1, "manifest": "workload.json", "sources": inputs.sources}:
        raise ValueError("Workload source inventory differs from frozen manifest")
    if (len(records) != len(inputs.cases) or any(
            record["name"] != case.name or record["setupSql"] != case.setup or record["migrationSql"] != case.sql
            or record["setupCommands"] != [case.setup]
            or record["profile"] != inputs.profile.to_wire() or record.get("part") != "workload"
            or record.get("features") != case.features
            or record["requirements"] != case.requirements
            or record.get("setupClockUnixMilliseconds") != inputs.setup_clock
            or [event["parameters"] for event in record["trace"]] != [
                [cell_wire(cell) for cell in row] for row in case.parameters]
            or case.clocks is not None and [event["clockUnixMilliseconds"] for event in record["trace"]] != case.clocks
            for record, case in zip(records, inputs.cases, strict=True))):
        raise ValueError("Workload membership or profile differs from frozen inventory")
    for record, case in zip(records, inputs.cases, strict=True):
        complete(case, record)
    return manifest, records


def report(directory: Path, corpus: Path, runtime: Path, *, generic: Path | None = None) -> dict[str, Json]:
    """Replay bound workload evidence and optionally combine it with the frozen generic corpus."""
    manifest, records = bound_records(directory, corpus)
    native_replay(records)
    workload = {"corpusVersion": manifest["corpusVersion"], "casesSha256": manifest["casesSha256"],
                "denominator": len(records), **replay(records, runtime)}
    result: dict[str, Json] = {"reportVersion": 1, "workload": workload,
                              "denominator": len(records), "counts": workload["counts"]}
    if generic is not None:
        generic_manifest, generic_records = load(generic)
        baseline = {"corpusVersion": generic_manifest["corpusVersion"],
                    "casesSha256": generic_manifest["casesSha256"], "denominator": len(generic_records),
                    **replay(generic_records, runtime)}
        result["generic"] = baseline
        result["denominator"] += len(generic_records)
        result["counts"] = dict(Counter(workload["counts"]) + Counter(baseline["counts"]))
    return result


def main() -> None:
    """Use one explicit directory for source data and another for immutable recorded evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("record", help="Record every inventory sequence and freeze its shards")
    capture.add_argument("directory", type=Path)
    capture.add_argument("--output", type=Path, required=True)
    for name in ("replay", "progress"):
        command = commands.add_parser(name)
        command.add_argument("directory", type=Path)
        command.add_argument("--corpus", type=Path, required=True)
        command.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
        command.add_argument("--output", type=Path, required=True)
        if name == "progress":
            command.add_argument("--generic", type=Path, required=True)
    args = parser.parse_args()
    result = record(args.directory, args.output) if args.command == "record" else report(
        args.directory, args.corpus, args.runtime_root.resolve(), generic=getattr(args, "generic", None))
    if args.command != "record":
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("recordedCases", "denominator", "counts") if key in result}))


if __name__ == "__main__":
    main()
