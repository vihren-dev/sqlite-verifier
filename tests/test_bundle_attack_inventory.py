"""The review matrix accounts for every independently selected old kernel attack."""

import ast
from pathlib import Path

from tests.kernel_attack_cases import PROOF_ATTACKS

ROOT = Path(__file__).resolve().parents[1]


def test_each_old_attack_has_a_named_bundle_boundary() -> None:
    """A new old-gate case must acquire a reviewed matrix entry instead of disappearing silently."""
    tree = ast.parse((ROOT / "tests/kernel_gate_test.py").read_text())
    functions = {node.name for node in tree.body if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")}
    cases = functions - {"test_proof_attack"}
    cases |= {f"test_proof_attack[{case.id}]" for case in PROOF_ATTACKS}
    matrix = (ROOT / "reports/20261006-bundle-attack-matrix.md").read_text()
    assert len(cases) == 19
    assert all(f"| `{case}` |" in matrix for case in cases)
    assert "compiled-module\nsubstitution is therefore specific to the old boundary" in matrix


def test_bundle_target_declares_shared_attack_inputs() -> None:
    """The independent bundle suite gets the actual fixture and hostile record sources in its sandbox."""
    definitions = (ROOT / "build-support/tests.nix").read_text()
    bundle = definitions.split('bundle = suite "bundle" {', 1)[1].split('cli = suite "cli" {', 1)[0]
    for name in ("kernel_fixture", "kernel_attack_cases", "bundle_attack_fixture", "bundle_hostile_records"):
        assert f"tests/{name}.py" in bundle
    assert "tests/kernel_gate" in bundle
