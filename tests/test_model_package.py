"""The standalone model and codec build independently and refuse application imports."""

import os
from pathlib import Path
import re
import shutil

import pytest

from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packages/belay-sqlite"
MODEL_MODULE_PREFIX = "Belay.Sqlite"
"""Only the standalone package namespace supplies project modules to the core."""
ALLOWED_EXTERNAL_IMPORT_ROOTS = {"Init", "Std"}
"""The core uses foundational libraries and excludes the Lean compiler API."""
EXPECTED_CORE_MODULE_COUNT = 14
"""The initial ownership inventory has thirteen model modules and the public root."""
pytestmark = [pytest.mark.integration, pytest.mark.requires_nix, pytest.mark.requires_lean("compiler")]


def test_core_import_closure_excludes_codec_and_application() -> None:
    """Follow the actual public root; no model import may reach Lean, codec or verifier modules."""
    pending = ["Belay.Sqlite"]
    reached: set[str] = set()
    while pending:
        module = pending.pop()
        if module in reached:
            continue
        reached.add(module)
        assert module != "Belay.Sqlite.Codec", module
        source = PACKAGE / (module.replace(".", "/") + ".lean")
        for line in re.findall(r"(?m)^import (.+)$", source.read_text()):
            for dependency in line.split():
                if dependency.startswith(MODEL_MODULE_PREFIX):
                    pending.append(dependency)
                else:
                    assert dependency.split(".")[0] in ALLOWED_EXTERNAL_IMPORT_ROOTS, (module, dependency)
    assert len(reached) == EXPECTED_CORE_MODULE_COUNT


@pytest.fixture(scope="module")
def model_artifact() -> Path:
    """Build the real component with its isolated fileset, pinned compiler and hardened sandbox."""
    result = run_command(["nix-build", "build-support/default.nix", "-A", "modelPackage",
        "--no-out-link", "--option", "sandbox", "true", "--option", "sandbox-fallback", "false",
        "--extra-experimental-features", "nix-command flakes"], cwd=ROOT, timeout=120)
    assert result.returncode == 0, result.diagnostic()
    return Path(result.stdout.strip())


def test_installed_core_and_codec_consumer(model_artifact: Path, lean_sysroot: Path,
                                           tmp_path: Path) -> None:
    """An unrelated consumer imports both libraries and checks transport roundtrip and refusal."""
    source = tmp_path / "Consumer.lean"
    source.write_text('''import Belay.Sqlite
import Belay.Sqlite.Codec
open Belay.Sqlite
#check Conforms.set
#check TableExtends.project
#check Conformance.statement_atomicity
def sample : GeneratedInputs := ⟨1, .sqlite351, [], [], []⟩
#eval match decodeGeneratedInputs (Lean.toJson sample) with
  | .ok result => result.version == 1 && result.schema.isEmpty && result.script.isEmpty
  | .error _ => false
#eval match decodeGeneratedInputs (Lean.toJson { sample with version := 2 }) with
  | .ok _ => false
  | .error _ => true
#eval match (Lean.fromJson? (Lean.toJson (256 : Nat)) : Except String UInt8) with
  | .ok _ => false
  | .error _ => true
''')
    library = model_artifact / ".lake/build/lib/lean"
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
        environment={**os.environ, "LEAN_PATH": str(library), "LEAN_SRC_PATH": str(model_artifact)}, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    assert result.stdout.splitlines().count("true") == 3, result.diagnostic()


def test_forbidden_application_import_fails_lake_build(
        lean_sysroot: Path, tmp_path: Path) -> None:
    """A real application checkout beside the isolated package cannot satisfy a model dependency."""
    package = tmp_path / "model"
    shutil.copytree(PACKAGE, package, ignore=shutil.ignore_patterns(".lake", "build"))
    shutil.copytree(ROOT / "SqliteVerifier", tmp_path / "application/SqliteVerifier")
    source = package / "Belay/Sqlite/Model.lean"
    source.write_text("import SqliteVerifier.Contract\n" + source.read_text())
    result = run_command([str(lean_sysroot / "bin/lake"), "build", "Belay.Sqlite"], cwd=package,
        environment={**os.environ, "LEAN_PATH": "", "LEAN_SRC_PATH": ""}, timeout=120)
    assert result.returncode != 0, result.diagnostic()
    assert "SqliteVerifier" in result.stdout + result.stderr, result.diagnostic()
