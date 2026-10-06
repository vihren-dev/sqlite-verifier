"""Stage evidence comes from the actual fresh launcher invocation, not a separate timing estimate."""

import ast
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from time import monotonic_ns

import pytest

OBSERVER = Path(__file__).resolve().parents[1] / "tools/bundle_measurement_child.py"


from tests.bundle_measurement_fixture import launcher


@pytest.mark.parametrize("arguments,exit_code,status", [([], 0, "VERIFIED"), (["negative"], 1, "VIOLATED"), (["error"], 1, "UNVERIFIED")])
def test_current_entrypoint_and_same_invocation_stage_spans(
        launcher: Path, tmp_path: Path, arguments: list[str], exit_code: int, status: str) -> None:
    """Original reports/exits survive observation, with identity-bound spans inside external wall bounds."""
    reports = []
    for index in range(2):
        trace = tmp_path / f"trace-{index}.json"
        started = monotonic_ns()
        result = subprocess.run([sys.executable, "-I", str(OBSERVER), "--launcher", str(launcher),
                                 "--trace", str(trace), "--", *arguments], capture_output=True, text=True, timeout=10)
        ended = monotonic_ns()
        assert result.returncode == exit_code, result.stderr
        report, stages = json.loads(result.stdout), json.loads(trace.read_text())
        assert report["status"] == status and report["count"] == report["isolated"] == 1
        assert report["pid"] == stages["pid"] and stages["active_stages"] == 0
        assert started <= stages["started_ns"] <= stages["ended_ns"] <= ended
        assert stages["launcher_sha256_before"] == stages["launcher_sha256_after"] == hashlib.sha256(launcher.read_bytes()).hexdigest()
        assert stages["observer_sha256"] == hashlib.sha256(OBSERVER.read_bytes()).hexdigest()
        assert {span["stage"] for span in stages["spans"]} == {
            "cli:verify", "contract:compile_contract", "process:dependencies",
            "process:compile:Proofs", "process:migration-bundle-checker"}
        outer = next(span for span in stages["spans"] if span["stage"] == "cli:verify")
        inner = next(span for span in stages["spans"] if span["stage"] == "contract:compile_contract")
        assert inner["parent_identifier"] == outer["identifier"]
        for span in stages["spans"]:
            assert stages["started_ns"] <= span["started_ns"] <= span["ended_ns"] <= stages["ended_ns"]
            assert span["source_sha256"] == hashlib.sha256(Path(span["source"]).read_bytes()).hexdigest()
        reports.append(report)
    assert reports[0]["pid"] != reports[1]["pid"]


def test_nonisolated_process_is_refused(launcher: Path, tmp_path: Path) -> None:
    """A measurement cannot silently use the caller's import environment."""
    trace = tmp_path / "trace.json"
    result = subprocess.run([sys.executable, str(OBSERVER), "--launcher", str(launcher), "--trace", str(trace)],
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 2 and "requires isolated Python" in result.stderr and not trace.exists()


def test_selected_stages_follow_current_driver_callers() -> None:
    """A removed or renamed caller cannot silently disappear from stage evidence."""
    from tools.bundle_measurement_child import STAGES
    root = OBSERVER.parents[1] / "migration_check"
    for module, function in STAGES:
        tree = ast.parse((root / f"{module}.py").read_text())
        assert function in {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}, (module, function)
