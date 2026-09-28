"""Execute each selected source scenario once, then aggregate that run's evidence."""

import json
import os
from pathlib import Path
import sys
import traceback
from uuid import uuid4

from tests.runtime_support import run_command
from tools.run_independent_suites import SUITES, run_suites

ROOT = Path(__file__).resolve().parents[1]
DEADLINES = {
    "collection": 30,
    "tests/test_toolchain_smoke.py": 15,
    "tests/parser_test.py": 30,
    "tests/parser_build_test.py": 30,
    "tests/docs_test.py": 15,
    "tests/coverage_test.py": 15,
    "legacy_unittest": 30,
    "tests/atuin_cli_test.py": 1500,
    "tests/compilation_test.py": 180,
    "tests/early_baseline_test.py": 180,
    "tests/environment_snapshot_test.py": 150,
    "tests/test_source_identity.py": 150,
    "tests/schema_generation_test.py": 75,
    "tests/coverage_evidence_test.py": 420,
    "tests/conformance_model_test.py": 420,
}

LEGACY_UNITTEST_MODULES = {
    "test_baseline_ci", "test_ci_scope", "test_cli_inputs", "test_independent_suites",
    "test_native_dependencies", "test_parser_cache_environment", "test_profiles", "test_resources",
    "test_runtime_package", "test_sandbox", "test_schema_baseline", "test_schema_translation",
    "test_sql_writes", "test_translation",
}


def partition_cases(cases: list[dict[str, object]], cached: set[str]) -> dict[str, tuple[str, ...]]:
    """Partition exact collected identities so source tests cannot run in two suites."""
    groups: dict[str, list[str]] = {}
    seen: set[str] = set()
    for case in cases:
        node = str(case["node_id"])
        if node in seen:
            raise ValueError(f"Duplicate collected case: {node}")
        seen.add(node)
        script = node.split("::", 1)[0]
        if script == "tests/runtime_package_test.py":
            raise ValueError("Installed package cases cannot enter the source suite")
        if node not in cached:
            group = "legacy_unittest" if (Path(script).name.startswith("test_")
                    and script != "tests/test_toolchain_smoke.py"
                    and Path(script).stem in LEGACY_UNITTEST_MODULES) else script
            groups.setdefault(group, []).append(node)
    if cached - seen:
        raise ValueError("Cached unit identities are absent from source collection")
    return {script: tuple(nodes) for script, nodes in groups.items()}


def main() -> int:
    """Collect without resources, apply reviewed cache evidence, and preserve all suite failures."""
    runtime = Path(os.environ.get("SQLITE_VERIFIER_RUNTIME_ROOT", ROOT)).resolve()
    run_id = str(uuid4())
    (ROOT / "build/coverage.json").unlink(missing_ok=True)
    catalogue = ROOT / "build/source-catalogue.json"
    catalogue.parent.mkdir(parents=True, exist_ok=True)
    catalogue.unlink(missing_ok=True)
    failure = None
    failed = 1
    try:
        result = run_command([sys.executable, "-m", "pytest", "tests",
                          "--ignore=tests/runtime_package_test.py", "--catalog-json", str(catalogue),
                          "--runtime-root", str(runtime), "--run-id", run_id], cwd=ROOT,
                          timeout=DEADLINES["collection"],
                          artifacts=ROOT / "build/test-logs/source-collection" / run_id)
        if result.returncode:
            raise RuntimeError(result.diagnostic())
        cases = json.loads(catalogue.read_text())
        cached: set[str] = set()
        if location := os.environ.get("SQLITE_VERIFIER_UNIT_CHECKS"):
            from tools.unit_cache import validated_cache
            cached = validated_cache(Path(location), cases, ROOT)
        selections = partition_cases(cases, cached)
        independent = tuple((script, deadline) for script, deadline in SUITES if script in selections)
        failed = run_suites(independent, runtime_root=runtime, run_id=run_id, selections=selections)
        remaining = tuple((script, DEADLINES.get(script, 60)) for script in selections
                          if script not in dict(SUITES))
        failed |= run_suites(remaining, max_workers=1, runtime_root=runtime,
                         run_id=run_id, selections=selections)
    except Exception:
        failure = traceback.format_exc()
        print(failure, file=sys.stderr, end="")
        failed = 1
    try:
        report = run_command([sys.executable, "conformance/coverage_report.py", "--run-id", run_id,
                          "--reports", "build/test-results/source", "--runtime-root", str(runtime),
                          "--output", "build/coverage.json"], cwd=ROOT, timeout=30,
                          artifacts=ROOT / "build/test-logs/source-coverage" / run_id)
        print(report.stdout + report.stderr, end="")
        failed |= report.returncode
        if not (ROOT / "build/coverage.json").is_file():
            raise RuntimeError(report.diagnostic())
        coverage = json.loads((ROOT / "build/coverage.json").read_text())
        if not isinstance(coverage, dict) or coverage.get("run_id") != run_id:
            raise ValueError("Coverage aggregation did not produce a current-run object")
        if report.returncode:
            coverage["status"] = "EVIDENCE_CHECKS_FAILED"
    except Exception:
        diagnostic = traceback.format_exc()
        print(diagnostic, file=sys.stderr, end="")
        coverage = {"report_version": 1, "run_id": run_id, "status": "EVIDENCE_CHECKS_FAILED",
                    "diagnostic": diagnostic}
        failed = 1
    if failure is not None:
        coverage.update(status="EVIDENCE_CHECKS_FAILED", orchestration_diagnostic=failure)
    (ROOT / "build/coverage.json").write_text(json.dumps(coverage, indent=2) + "\n")
    return int(bool(failed or coverage.get("status") != "EVIDENCE_CHECKS_PASSED"))


if __name__ == "__main__":
    raise SystemExit(main())
