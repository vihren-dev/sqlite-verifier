"""Measure explicit Lean match-arm hits and real SQLite gcov branches on admitted cases."""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from conformance.case_format import Json
from conformance.corpus import load
from conformance.model_check import compiled_many
from conformance.native_replay import prepare
from conformance.record_parser import runtime_library


def workload(runtime: Path, generated: Path) -> tuple[list[dict[str, Json]], dict[str, int]]:
    """Keep generated and frozen denominators explicit, including all five authored originals."""
    cases = [json.loads(line) for line in (generated / "cases.jsonl").read_text().splitlines()]
    cases += [json.loads(path.read_text()) for path in sorted(Path("conformance/cases").glob("*.json"))]
    counts: Counter[str] = Counter()
    for record in load(Path("conformance/corpus-v3"))[1]:
        case, error = prepare(record, runtime_library(runtime))
        if case is not None:
            cases.append(case)
        else:
            assert error["verdict"] == "MODEL_UNSUPPORTED", error
            counts[error["verdict"]] += 1
    answers = compiled_many(cases, runtime)
    assert all(answer["verdict"] in ("AGREE", "MODEL_UNSUPPORTED") for answer in answers), answers
    counts.update(answer["verdict"] for answer in answers)
    return [case for case, answer in zip(cases, answers, strict=True) if answer["verdict"] == "AGREE"], dict(counts)


def constructors(declaration: str) -> list[str]:
    """Derive constructor denominators from the measured source, including future model additions."""
    source = Path("packages/belay-sqlite/Belay/Sqlite/Execution.lean").read_text()
    body = source.split(f"inductive {declaration} where\n", 1)[1].split("  deriving", 1)[0]
    names = re.findall(r"^  \| (\w+)", body, re.MULTILINE)
    if not names:
        raise ValueError(f"No constructors found for {declaration}")
    return names


def model_coverage(cases: list[dict[str, Json]], instrumented: Path, runtime: Path) -> dict[str, Json]:
    """Instrumentation must preserve every ordinary verdict and first disagreement position."""
    result = subprocess.run([str(instrumented / ".lake/build/bin/conformance-runner")],
        input="".join(json.dumps(case) + "\n" for case in cases), text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    answers = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    ordinary = compiled_many(cases, runtime)
    assert [{key: answer[key] for key in ("verdict", "position")} for answer in answers] == ordinary
    hits = Counter(re.findall(r"COVER\|([^\s]+)", result.stdout + result.stderr))
    sites = json.loads((instrumented / "coverage-sites.json").read_text())
    assert not set(hits) - {site["id"] for site in sites}
    executed_constructors = Counter(next(iter(item)) if isinstance(item, dict) else item
                           for answer in answers for item in answer["executed"])
    errors = Counter(error for answer in answers for error in re.findall(r"ExecutionError\.(\w+)", answer["modelError"]))
    return {"scope": "Explicit match arms in step, finish, literalStep, statementReady, advance, runSqlFrom, supportedSqlFrom",
        "limitations": "Not every helper or Boolean branch; debug identity instrumentation, not proof evidence. Counts include classifier admission and diagnostic re-execution.",
        "instrumentedRuntime": str(instrumented), "armsCovered": sum(bool(hits[site["id"]]) for site in sites),
        "armsTotal": len(sites), "arms": [{**site, "hits": hits[site["id"]]} for site in sites],
        "constructors": {name: executed_constructors[name] for name in constructors("Statement")},
        "errors": {name: errors[name] for name in constructors("ExecutionError")}}


def gcov_counts(text: str) -> dict[str, Json]:
    """Count real branch arcs only within functions called by this execution, including untaken arcs."""
    functions: dict[str, dict[str, int]] = {}
    current: dict[str, int] | None = None
    for line in text.splitlines():
        function = re.match(r"function (\S+) called (\d+)", line)
        if function:
            current = {"calls": int(function[2]), "branches": 0, "taken": 0}
            functions[function[1]] = current
        elif current is not None and line.startswith("branch "):
            current["branches"] += 1
            taken = re.search(r"taken (\d+)", line)
            current["taken"] += bool(taken and int(taken[1]))
    reached = {name: counts for name, counts in functions.items() if counts["calls"]}
    if not reached or not sum(counts["branches"] for counts in reached.values()):
        raise ValueError("gcov did not report any executed functions/branches")
    return {"functionsReached": len(reached), "functionsInReport": len(functions),
        "branchesInReachedFunctions": sum(counts["branches"] for counts in reached.values()),
        "branchesTaken": sum(counts["taken"] for counts in reached.values()), "functions": reached}


def main() -> None:
    """Use fresh counter storage, bounded child processes, and reproducible source/case digests."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--model", type=Path, default=Path("build/model-coverage"))
    parser.add_argument("--native", type=Path, default=Path("build/native-coverage"))
    parser.add_argument("--generated", type=Path, default=Path("build/generated"))
    parser.add_argument("--llvm-cov", required=True)
    parser.add_argument("--output", type=Path, default=Path("build/coverage"))
    args = parser.parse_args()
    runtime, native = args.runtime_root.resolve(), args.native.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    cases, workload_counts = workload(runtime, args.generated)
    payload = "".join(json.dumps(case) + "\n" for case in cases)
    casefile = args.output / "cases.jsonl"
    casefile.write_text(payload)
    model = model_coverage(cases, args.model.resolve(), runtime)
    counters = args.output / "gcov"
    counters.mkdir(exist_ok=True)
    if list(counters.glob("*.gcda")):
        raise ValueError("Coverage output already contains counters; select a fresh output directory")
    for name in ("sqlite3.c", "sqlite3.gcno"):
        shutil.copyfile(native / name, counters / name)
    library = next(native.glob("libsqlite3.*"))
    run = subprocess.run([sys.executable, "-m", "conformance.measure_native", str(casefile),
        "--library", str(library), "--runtime-root", str(runtime)], capture_output=True, text=True, timeout=120,
        env={**os.environ, "GCOV_PREFIX": str(counters.resolve()), "GCOV_PREFIX_STRIP": "100"})
    if run.returncode:
        raise RuntimeError(run.stdout + run.stderr)
    measured = subprocess.run([args.llvm_cov, "gcov", "-b", "-c", "-f", "sqlite3.gcno"],
        cwd=counters, capture_output=True, text=True, timeout=60)
    if measured.returncode:
        raise RuntimeError(measured.stdout + measured.stderr)
    (counters / "gcov.log").write_text(measured.stdout + measured.stderr)
    gcov = gcov_counts((counters / "sqlite3.c.gcov").read_text())
    assert not {"sqlite3_open", "sqlite3_close", "sqlite3_bind_int64"} & gcov["functions"].keys(), "Fixture/cleanup counters leaked"
    version = subprocess.run([args.llvm_cov, "--version"], capture_output=True, text=True, timeout=10)
    gcov.update(tool=version.stdout.strip(), library=str(library),
        sourceSha256=hashlib.sha256((native / "sqlite3.c").read_bytes()).hexdigest(),
        scope="Migration statements only (prepare/step/finalize); reset before each, dump and reset after each; fixture/observation/connection cleanup excluded. Separately compiled -O0 gcov library")
    result = {"cases": len(cases), "workloadCounts": workload_counts,
              "corpusVersion": 3, "corpusSha256": load(Path("conformance/corpus-v3"))[0]["casesSha256"],
              "sourceSha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in [*sorted(Path("packages/belay-sqlite/Belay/Sqlite").glob("*.lean")), Path(__file__),
                      Path("conformance/instrument_model.py"), Path("conformance/measure_native.py"),
                      Path("conformance/native_trace.py"), Path("conformance/native_connection.py")]},
              "casesSha256": hashlib.sha256(payload.encode()).hexdigest(),
              "model": model, "native": gcov}
    (args.output / "report.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"cases": len(cases), "arms": [model["armsCovered"], model["armsTotal"]],
                      "nativeBranches": [gcov["branchesTaken"], gcov["branchesInReachedFunctions"]]}))


if __name__ == "__main__":
    main()
