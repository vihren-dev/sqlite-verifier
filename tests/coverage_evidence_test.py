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


@pytest.mark.parser
@pytest.mark.requires_native
@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_grammar_inventory(version: str, runtime_root: Path,
                           command_runner: Callable[..., CommandResult]) -> None:
    """The pinned upstream default grammar and generated syntax have equal positive production counts."""
    directory = "parser" if version == "3.51.0" else "parser-3.46.0"
    upstream = "upstream" if version == "3.51.0" else "upstream-3.46.0"
    result = command_runner([str(runtime_root / "build" / directory / "lemon"), "-g",
                             str(ROOT / "parser" / upstream / "parse.y")], cwd=ROOT, timeout=5)
    assert result.returncode == 0, result.diagnostic()
    generated = sum("::=" in line for line in (runtime_root / "build" / directory / "syntax.y").read_text().splitlines())
    assert generated > 0 and generated == sum("::=" in line for line in result.stdout.splitlines())


@pytest.mark.kernel
@pytest.mark.requires_lean
def test_named_proofs(lean_sysroot: Path, lean_library: Path, tmp_path: Path,
                      command_runner: Callable[..., CommandResult]) -> None:
    """All catalogued model theorems exist and their exact axiom sets stay within the trusted allowance."""
    source = tmp_path / "Audit.lean"
    source.write_text("import SqliteVerifier\n" + "\n".join(
        f"#check {name}\n#print axioms {name}" for name in THEOREMS) + "\n")
    result = command_runner([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
                             environment={**os.environ, "LEAN_PATH": str(lean_library)}, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    assert audit_problems(result.stdout) == [], result.stdout


def test_axiom_audit_rejects_missing_and_untrusted() -> None:
    """The audit fails for a missing theorem and for `sorryAx`, so the named-proof check can fail."""
    trusted = "\n".join(f"'{name}' depends on axioms: [propext, Quot.sound]" for name in THEOREMS)
    assert audit_problems(trusted) == []
    tainted = trusted.replace("[propext, Quot.sound]", "[propext, sorryAx]", 1)
    assert audit_problems(tainted) == [f"{THEOREMS[0]} uses untrusted axioms: ['sorryAx']"]
    assert audit_problems(trusted.split("\n", 1)[1]) == [f"missing theorem: {THEOREMS[0]}"]
