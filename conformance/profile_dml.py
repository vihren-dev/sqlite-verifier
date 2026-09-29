"""Measure acquisition and compiled classification separately on a fixed transaction/DML mix."""

import argparse
import cProfile
import hashlib
import json
from pathlib import Path
import pstats
import time

from conformance.model_check import acquire, compiled_many
from conformance import native_trace
from conformance.native_trace import Fixture


def main() -> None:
    """Record reproducible stage timings and the dominant cumulative Python costs."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--uncached", action="store_true")
    args = parser.parse_args()
    if args.uncached:
        native_trace.parsed_schema = native_trace.parsed_schema.__wrapped__
    runtime = args.runtime_root.resolve()
    profiler = cProfile.Profile()
    profiler.enable()
    cases = []
    started = time.perf_counter()
    for index in range(40):
        ending = ("COMMIT;", "ROLLBACK;", "", "INSERT INTO t(id,v) VALUES(2,NULL); COMMIT;")[index % 4]
        fixture = Fixture("CREATE TABLE t(id INTEGER NOT NULL,v BLOB,UNIQUE(id));",
            "BEGIN; INSERT INTO t(id,v) VALUES(2,X''); UPDATE t SET v=X'ff' WHERE id=1; " + ending,
            {"t": [(1, ((1, 1), (4, b"")))]}, f"dml-{index}")
        case, error = acquire(fixture, runtime)
        if case is None:
            raise RuntimeError(str(error))
        cases.append(case)
    acquired = time.perf_counter()
    answers = compiled_many(cases, runtime)
    finished = time.perf_counter()
    profiler.disable()
    assert all(answer["verdict"] == "AGREE" for answer in answers), answers
    result = {"cases": len(cases), "schemaCache": not args.uncached,
              "workload": "40 cases: BEGIN, INSERT, UPDATE; equal COMMIT/ROLLBACK/open/constraint-error endings",
              "nativeAcquisitionSeconds": acquired - started, "compiledBatchSeconds": finished - acquired,
              "casesPerSecond": len(cases) / (finished - started), "runtime": str(runtime),
              "sourceSha256": {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                               for name in ("profile_dml.py", "native_trace.py", "model_check.py")}}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    pstats.Stats(profiler).sort_stats("cumulative").print_stats(20)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
