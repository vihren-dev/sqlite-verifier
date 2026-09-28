"""Prove exact source selection and reject incomplete or unsafe cached unit evidence."""

import copy
import json
from pathlib import Path
import shutil

import pytest

from tools.run_source_suite import partition_cases
from tools.unit_cache import validated_cache
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.unit, pytest.mark.environment]
ROOT = Path(__file__).resolve().parents[1]


def test_source_partition() -> None:
    """Every uncached identity appears once, with legacy unit scripts grouped together."""
    nodes = ["tests/kernel_gate_test.py::test_a", "tests/cli_test.py::test_b",
             "tests/test_profiles.py::test_c", "tests/test_sandbox.py::test_d",
             "tests/atuin_cli_test.py::test_e"]
    selected = partition_cases([{"node_id": node} for node in nodes], {nodes[2]})
    assert sorted(node for group in selected.values() for node in group) == sorted(set(nodes) - {nodes[2]})
    assert selected["legacy_unittest"] == (nodes[3],)
    assert selected["tests/atuin_cli_test.py"] == (nodes[4],)


@pytest.mark.parametrize("nodes,cached,message", [
    (["tests/x.py::test_a"] * 2, set(), "Duplicate"),
    (["tests/runtime_package_test.py::test_a"], set(), "Installed"),
    (["tests/x.py::test_a"], {"tests/x.py::test_b"}, "absent"),
], ids=["duplicate", "installed", "unknown-cache"])
def test_invalid_source_partition(nodes: list[str], cached: set[str], message: str) -> None:
    """Selection errors fail before a suite can silently omit or duplicate work."""
    with pytest.raises(ValueError, match=message):
        partition_cases([{"node_id": node} for node in nodes], cached)


@pytest.mark.parametrize("mutation", ["valid", "manifest", "catalogue", "host-resource", "integration",
                                      "missing-phase", "skipped", "failed-exit", "wrong-runtime", "stale-derivation", "readonly-rerun", "missing-junit"],
                         ids=str)
def test_cached_unit_evidence(tmp_path: Path, mutation: str, monkeypatch: pytest.MonkeyPatch) -> None:
    """Only exact, currently resource-free units with all three passed phases can be excluded."""
    source, cache = tmp_path / "source", tmp_path / "cache"
    (source / "build-support").mkdir(parents=True)
    (cache / "source").mkdir(parents=True)
    shutil.copy2(ROOT / "build-support/run_unit_checks.py", source / "build-support/run_unit_checks.py")
    expected_path = cache if mutation != "stale-derivation" else tmp_path / "new-output"
    def evaluate_identity(*args: object, **kwargs: object) -> CommandResult:
        """Supply a known Nix evaluation result without making this unit check need Nix."""
        return CommandResult(("nix-instantiate",), 0, json.dumps(str(expected_path)), "", 0)
    monkeypatch.setattr("tools.unit_cache.run_command", evaluate_identity)
    nodes = ["tests/test_sample.py::test_a"]
    cases = [{"node_id": nodes[0], "level": "unit", "resources": []}]
    manifest = nodes if mutation != "manifest" else ["tests/test_sample.py::test_other"]
    catalogue = copy.deepcopy(cases) if mutation != "catalogue" else []
    report = {"runtime": "source", "suite": "unit", "exit_code": 0,
              "cases": [{**cases[0], "phases": {phase: {"outcome": "passed"}
                         for phase in ("setup", "call", "teardown")}}]}
    if mutation == "host-resource":
        cases[0]["resources"] = ["requires_lean"]
    if mutation == "integration":
        cases[0]["level"] = "integration"
    if mutation == "missing-phase":
        del report["cases"][0]["phases"]["teardown"]
    if mutation == "skipped":
        report["cases"][0]["phases"]["call"]["outcome"] = "skipped"
    if mutation == "failed-exit":
        report["exit_code"] = 1
    if mutation == "wrong-runtime":
        report["runtime"] = "installed"
    for path, value in [(source / "build-support/unit-cases.json", nodes),
                        (cache / "unit-cases.json", manifest), (cache / "catalogue.json", catalogue),
                        (cache / "source/unit.json", report)]:
        path.write_text(json.dumps(value))
    if mutation != "missing-junit":
        (cache / "source/unit.xml").write_text('<testsuites><testsuite tests="1"/></testsuites>')
    if mutation in {"valid", "readonly-rerun"}:
        assert validated_cache(cache, cases, source) == set(nodes)
        assert json.loads((source / "build/cached-unit/source/unit.json").read_text()) == report
        assert not (source / "build/test-results").exists()
        assert (source / "build/cached-unit/source/unit.xml").read_bytes() == (cache / "source/unit.xml").read_bytes()
        if mutation == "readonly-rerun":
            destination = source / "build/cached-unit"
            for path in destination.rglob("*"):
                path.chmod(0o555 if path.is_dir() else 0o444)
            destination.chmod(0o555)
            assert validated_cache(cache, cases, source) == set(nodes)
            assert (destination / "source/unit.xml").read_bytes() == (cache / "source/unit.xml").read_bytes()
    else:
        with pytest.raises((ValueError, OSError)):
            validated_cache(cache, cases, source)
        assert not (source / "build/cached-unit").exists()
