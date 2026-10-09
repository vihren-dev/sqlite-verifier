"""Check grammar completeness and the trusted axiom scope of the catalogued model theorems."""

from collections.abc import Callable
import os
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from coverage_catalog import THEOREMS
from coverage_evidence import audit_problems
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.integration, pytest.mark.conformance]


@pytest.mark.kernel
@pytest.mark.requires_lean
def test_named_proofs(lean_sysroot: Path, lean_libraries: tuple[Path, Path], tmp_path: Path,
                      command_runner: Callable[..., CommandResult]) -> None:
    """All catalogued model theorems exist and their exact axiom sets stay within the trusted allowance."""
    source = tmp_path / "Audit.lean"
    source.write_text("import SqliteVerifier\nimport SqliteVerifier.Examples\nimport SqliteVerifier.ReverseDemonstration\nimport SqliteVerifier.FailureDemonstration\n" + "\n".join(
        f"#check {name}\n#print axioms {name}" for name in THEOREMS) + "\n")
    result = command_runner([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
                             environment={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_libraries))}, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    assert audit_problems(result.stdout) == [], result.stdout


def test_axiom_audit_rejects_missing_and_untrusted() -> None:
    """The audit fails for a missing theorem and for `sorryAx`, so the named-proof check can fail."""
    trusted = "\n".join(f"'{name}' depends on axioms: [propext, Quot.sound]" for name in THEOREMS)
    assert audit_problems(trusted) == []
    tainted = trusted.replace("[propext, Quot.sound]", "[propext, sorryAx]", 1)
    assert audit_problems(tainted) == [f"{THEOREMS[0]} uses untrusted axioms: ['sorryAx']"]
    assert audit_problems(trusted.split("\n", 1)[1]) == [f"missing theorem: {THEOREMS[0]}"]
