"""Produce grammar and theorem receipts once, independently of aggregate report generation."""

from collections.abc import Callable
import json
import os
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from coverage_catalog import THEOREMS
from coverage_evidence import audit_proofs
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.integration, pytest.mark.conformance]


def receipt(result: CommandResult, path: Path) -> dict[str, object]:
    """Retain the bounded command's original diagnostics in the coverage schema."""
    value = {"status": "PASSED" if result.returncode == 0 else "FAILED",
             "exit_code": result.returncode, "stdout": result.stdout,
             "stderr": result.stderr, "command": list(result.command)}
    path.write_text(json.dumps(value, indent=2) + "\n")
    return value


@pytest.mark.parser
@pytest.mark.requires_native
@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_grammar_inventory(version: str, runtime_root: Path, case_artifacts: Path,
                           command_runner: Callable[..., CommandResult]) -> None:
    """The pinned upstream default grammar and generated syntax have equal positive production counts."""
    directory = "parser" if version == "3.51.0" else "parser-3.46.0"
    upstream = "upstream" if version == "3.51.0" else "upstream-3.46.0"
    result = command_runner([str(runtime_root / "build" / directory / "lemon"), "-g",
                             str(ROOT / "parser" / upstream / "parse.y")], cwd=ROOT, timeout=5)
    receipt(result, case_artifacts / "grammar.json")
    assert result.returncode == 0, result.diagnostic()
    generated = sum("::=" in line for line in (runtime_root / "build" / directory / "syntax.y").read_text().splitlines())
    assert generated > 0 and generated == sum("::=" in line for line in result.stdout.splitlines())


@pytest.mark.kernel
@pytest.mark.requires_lean
def test_proof_build(lean_sysroot: Path, lean_library: Path, tmp_path: Path,
                     case_artifacts: Path, command_runner: Callable[..., CommandResult]) -> None:
    """The selected built proof library loads freshly with the pinned compiler, without rebuilding."""
    source = tmp_path / "Library.lean"
    source.write_text("import SqliteVerifier\n")
    result = command_runner([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
                             environment={**os.environ, "LEAN_PATH": str(lean_library)}, timeout=30)
    receipt(result, case_artifacts / "proof-build.json")
    assert result.returncode == 0, result.diagnostic()


@pytest.mark.kernel
@pytest.mark.requires_lean
def test_named_proofs(lean_sysroot: Path, lean_library: Path, tmp_path: Path,
                      case_artifacts: Path, command_runner: Callable[..., CommandResult]) -> None:
    """All catalogued model theorems exist and their exact axiom sets stay within the trusted allowance."""
    source = tmp_path / "Audit.lean"
    source.write_text("import SqliteVerifier\n" + "\n".join(
        f"#check {name}\n#print axioms {name}" for name in THEOREMS) + "\n")
    result = command_runner([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
                             environment={**os.environ, "LEAN_PATH": str(lean_library)}, timeout=30)
    evidence = audit_proofs(receipt(result, case_artifacts / "named-proofs.json"))
    (case_artifacts / "named-proofs.json").write_text(json.dumps(evidence, indent=2) + "\n")
    assert evidence["status"] == "PASSED", evidence


def test_fresh_coverage_report(tmp_path: Path, command_runner: Callable[..., CommandResult]) -> None:
    """A previous success file never replaces absent current-run receipts; failure JSON is still written."""
    output = tmp_path / "coverage.json"
    output.write_text('{"status":"EVIDENCE_CHECKS_PASSED"}\n')
    result = command_runner([sys.executable, str(ROOT / "conformance/coverage_report.py"),
        "--reports", str(tmp_path / "source"), "--run-id", "missing-fresh-run",
        "--runtime-root", str(ROOT), "--output", str(output)], cwd=ROOT, timeout=5)
    assert result.returncode == 1, result.diagnostic()
    report = json.loads(output.read_text())
    assert report["status"] == "EVIDENCE_CHECKS_FAILED"
    assert report["native_model"]["observed_discrepancies"] is None
    assert report["atuin_sql"]["observed_discrepancies"] is None
