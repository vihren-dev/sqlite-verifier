"""Cache only an explicitly reviewed set of resource-free, completely passing unit cases."""

import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def validate_cases(expected: list[str], cases: list[dict[str, object]], *, executed: bool) -> None:
    """Reject selection drift, resource use, non-unit cases and incomplete/skipped execution."""
    if sorted(case["node_id"] for case in cases) != expected:
        raise ValueError("Cached unit catalogue differs from the reviewed node inventory")
    for case in cases:
        if case["level"] != "unit" or case["resources"] != []:
            raise ValueError(f"Cached case requires host resources or is not unit: {case['node_id']}")
        if executed:
            phases = case["phases"]
            if not isinstance(phases, dict) or set(phases) != {"setup", "call", "teardown"}:
                raise ValueError(f"Cached case did not execute all phases: {case['node_id']}")
            if any(phase["outcome"] != "passed" for phase in phases.values()):
                raise ValueError(f"Cached case failed or skipped: {case['node_id']}")


def main() -> None:
    """Validate collection before fixture setup, then retain exact selection and phase evidence."""
    destination = Path(sys.argv[1]).resolve()
    inventory = ROOT / "build-support/unit-cases.json"
    expected = json.loads(inventory.read_text())
    if (not isinstance(expected, list) or not expected
            or not all(isinstance(node, str) for node in expected)
            or expected != sorted(set(expected))):
        raise ValueError("Unit inventory must be a nonempty sorted list of unique node IDs")
    destination.mkdir(parents=True, exist_ok=True)
    arguments = [sys.executable, "-m", "pytest", *expected, "-q",
                 "--report-dir", str(destination), "--suite", "unit"]
    catalogue = destination / "catalogue.json"
    subprocess.run([*arguments, "--catalog-json", str(catalogue)], cwd=ROOT, check=True, timeout=30)
    validate_cases(expected, json.loads(catalogue.read_text()), executed=False)
    subprocess.run(arguments, cwd=ROOT, check=True, timeout=60)
    report = json.loads((destination / "source/unit.json").read_text())
    if report["exit_code"] != 0:
        raise ValueError("Cached unit run failed")
    validate_cases(expected, report["cases"], executed=True)
    shutil.copy2(inventory, destination / "unit-cases.json")


if __name__ == "__main__":
    main()
