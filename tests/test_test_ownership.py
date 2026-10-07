"""Host collection preserves source checks and excludes every delegated Nix suite."""

import json
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.unit, pytest.mark.environment]


def test_host_collection_retains_source_owned_conformance_checks() -> None:
    """Use actual pytest discovery so the shared ownership list cannot silently lose host tests."""
    result = subprocess.run([sys.executable, "-m", "pytest", "--collect-only", "-q", "tests",
                             "--source-checks", "-m", "not requires_nix"],
                            cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    collected = {line.split("::")[0] for line in result.stdout.splitlines() if "::" in line}
    suites = json.loads((ROOT / "tests/nix_suites.json").read_text())
    delegated = {name for files in suites.values() for name in files}
    assert not collected & delegated
    assert "tests/runtime_package_test.py" not in collected
    assert {"tests/conformance_axioms_test.py", "tests/conformance_native_test.py",
            "tests/test_ci_checks.py", "tests/test_test_ownership.py"} <= collected
    assert all((ROOT / name).is_file() for name in delegated)


def test_each_delegated_file_belongs_to_one_suite() -> None:
    """A file in two suites would run twice and rerun when either suite's inputs change."""
    suites = json.loads((ROOT / "tests/nix_suites.json").read_text())
    owners: dict[str, list[str]] = {}
    for suite, files in suites.items():
        for name in files:
            owners.setdefault(name, []).append(suite)
    shared = {name: names for name, names in owners.items() if len(names) > 1}
    assert not shared, f"Test files listed in more than one Nix suite: {shared}"


@pytest.mark.requires_native("just")
def test_recipe_expansion_retains_full_model_in_release_checks() -> None:
    """Actual just dependencies select the sample for development and the full set for releases."""
    for recipe, target in (("test", "developmentTests"), ("test-full", "tests"), ("package", "tests")):
        result = subprocess.run(["just", "--dry-run", recipe], cwd=ROOT,
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, result.stdout + result.stderr
        commands = result.stdout + result.stderr
        assert f"-A {target} --out-link build/nix-tests" in commands
        if recipe != "test":
            assert "-A developmentTests" not in commands
