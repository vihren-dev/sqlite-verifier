"""Run ADR 0004 native cases, the compiled authority, and optional kernel regressions."""

import argparse
import json
import os
from pathlib import Path
import time

from conformance.case_format import Json, literal_cell
from conformance.model_cases import cases, schema_sql
from conformance.native_trace import Fixture
from conformance.model_check import acquire, compiled_many, prove
from conformance.native_connection import SOURCE_ID, library_path


def fixtures() -> tuple[Fixture, ...]:
    """Preserve the five independent authored fixtures, including their physical rowids."""
    return tuple(Fixture(schema_sql(case.before), case.migration,
                         {table.name: [(int(row[0]), tuple(literal_cell(cell) for cell in row[1:]))
                                       for row in table.rows] for table in case.before}, case.name)
                 for case in cases())


def main() -> int:
    """Record reproducible evidence and timings; never authorize W3 automatically."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--prove", action="store_true")
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be positive")
    runtime = args.runtime_root.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    reports: list[dict[str, Json]] = []
    pending: list[tuple[Fixture, int, dict[str, Json]]] = []
    start = time.monotonic()
    for iteration in range(args.repeat):
        for fixture in fixtures():
            case, result = acquire(fixture, runtime)
            reports.append({"fixture": fixture.name, "iteration": iteration, **result})
            if case is not None:
                pending.append((fixture, len(reports) - 1, case))
    native_seconds = time.monotonic() - start
    start = time.monotonic()
    results = compiled_many([case for _, _, case in pending], runtime, emit_lean=args.prove)
    compiled_seconds = time.monotonic() - start
    for (fixture, index, case), result in zip(pending, results, strict=True):
        reports[index].update({key: value for key, value in result.items() if key not in {"decoded", "caseLean"}})
        if reports[index]["iteration"] == 0:
            (args.output / f"{fixture.name}.json").write_text(json.dumps(case, indent=2) + "\n")
            if args.prove and result["verdict"] == "AGREE":
                term = result.get("caseLean")
                if not isinstance(term, str):
                    raise ValueError("Missing decoded proof term")
                failure = next(c.lean_failure for c in cases() if c.name == fixture.name)
                prove(term, runtime, args.output / f"{fixture.name}.lean", case=case, failure=failure)
    elapsed = native_seconds + compiled_seconds
    observations = sum(len(case["nativeTrace"]) for _, _, case in pending)
    report = {"cases": reports, "secondsIncludingNativeSnapshots": elapsed,
              "casesPerSecond": len(reports) / elapsed, "kernelProofTimeIncluded": False,
              "nativeObservationCount": observations,
              "nativeAcquisitionSeconds": native_seconds, "compiledBatchSeconds": compiled_seconds,
              "runnerProcesses": 1, "proofTermEmissionIncluded": args.prove,
              "runtime": str(runtime), "sqliteLibrary": str(library_path()), "sqliteSourceId": SOURCE_ID,
              "platform": os.uname().sysname + "-" + os.uname().machine}
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if all(row["verdict"] == "AGREE" for row in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
