"""Run ADR 0004 native cases, the compiled authority, and optional kernel regressions."""

import argparse
import json
import os
from pathlib import Path
import time

from conformance.case_format import Json, literal_cell
from conformance.model_cases import cases, schema_sql
from conformance.native_trace import Fixture
from conformance.model_check import compiled, evaluate, prove
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
    elapsed = 0.0
    observations = 0
    for iteration in range(args.repeat):
        for fixture in fixtures():
            start = time.monotonic()
            case, result = evaluate(fixture, runtime)
            elapsed += time.monotonic() - start
            if case is not None:
                observations += len(case["nativeTrace"])
            reports.append({"fixture": fixture.name, "iteration": iteration, **result})
            if case is not None and iteration == 0:
                (args.output / f"{fixture.name}.json").write_text(json.dumps(case, indent=2) + "\n")
                if args.prove and result["verdict"] == "AGREE":
                    emitted = compiled(case, runtime, emit_lean=True)
                    term = emitted.get("caseLean")
                    if not isinstance(term, str):
                        raise ValueError("Missing decoded proof term")
                    failure = next(case.lean_failure for case in cases() if case.name == fixture.name)
                    prove(term, runtime, args.output / f"{fixture.name}.lean", failure=failure)
    report = {"cases": reports, "secondsIncludingNativeSnapshots": elapsed,
              "casesPerSecond": len(reports) / elapsed, "kernelProofTimeIncluded": False,
              "nativeObservationCount": observations,
              "runtime": str(runtime), "sqliteLibrary": str(library_path()), "sqliteSourceId": SOURCE_ID,
              "platform": os.uname().sysname + "-" + os.uname().machine}
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if all(row["verdict"] == "AGREE" for row in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
