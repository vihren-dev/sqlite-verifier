"""Accept only exact, resource-free unit evidence from the reviewed Nix target."""

import importlib.util
import json
from pathlib import Path
import shutil

from tests.runtime_support import run_command


def validated_cache(location: Path, cases: list[dict[str, object]], root: Path) -> set[str]:
    """Validate current selection and every cached execution phase before excluding any case."""
    identity = run_command(["nix-instantiate", "--eval", "--strict", "--json",
                            "build-support/default.nix", "-A", "unitChecks.outPath"],
                           cwd=root, timeout=60)
    if identity.returncode:
        raise ValueError(f"Cannot evaluate current unit derivation: {identity.diagnostic()}")
    expected_path = Path(json.loads(identity.stdout))
    if location.resolve(strict=True) != expected_path:
        raise ValueError("Cached unit output differs from the current source derivation")
    specification = importlib.util.spec_from_file_location(
        "unit_checks_validator", root / "build-support/run_unit_checks.py")
    if specification is None or specification.loader is None:
        raise ValueError("Missing reviewed unit cache validator")
    validator = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(validator)
    expected = json.loads((root / "build-support/unit-cases.json").read_text())
    if (not isinstance(expected, list) or not expected
            or not all(isinstance(node, str) for node in expected)
            or expected != sorted(set(expected))):
        raise ValueError("Unit inventory must be a nonempty sorted unique list")
    if json.loads((location / "unit-cases.json").read_text()) != expected:
        raise ValueError("Cached unit manifest differs from this source checkout")
    selected = set(expected)
    validator.validate_cases(expected, [case for case in cases if case["node_id"] in selected],
                             executed=False)
    validator.validate_cases(expected, json.loads((location / "catalogue.json").read_text()),
                             executed=False)
    report = json.loads((location / "source/unit.json").read_text())
    if report["exit_code"] != 0 or report["runtime"] != "source" or report["suite"] != "unit":
        raise ValueError("Cached unit report failed or identifies a different suite/runtime")
    validator.validate_cases(expected, report["cases"], executed=True)
    destination = root / "build/cached-unit"
    destination.mkdir(parents=True, exist_ok=True)
    for relative in ("unit-cases.json", "catalogue.json", "source/unit.json"):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(location / relative, target)
    (destination / "origin.json").write_text(json.dumps({"unit_checks": str(location.resolve())}) + "\n")
    return selected
