"""Execute each selected source scenario once, then aggregate that run's evidence."""

import json
import os
from pathlib import Path
import sys
from uuid import uuid4

from tests.runtime_support import run_command
from tools.run_independent_suites import SUITES, run_suites

ROOT = Path(__file__).resolve().parents[1]
DEADLINES = {
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
    result = run_command([sys.executable, "-m", "pytest", "tests",
                          "--ignore=tests/runtime_package_test.py", "--catalog-json", str(catalogue),
                          "--runtime-root", str(runtime), "--run-id", run_id], cwd=ROOT, timeout=30)
    if result.returncode:
        print(result.diagnostic(), file=sys.stderr)
        return result.returncode
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
    report = run_command([sys.executable, "conformance/coverage_report.py", "--run-id", run_id,
                          "--reports", "build/test-results/source", "--runtime-root", str(runtime),
                          "--output", "build/coverage.json"], cwd=ROOT, timeout=30)
    print(report.stdout + report.stderr, end="")
    return int(bool(failed or report.returncode))


if __name__ == "__main__":
    raise SystemExit(main())
