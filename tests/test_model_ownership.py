"""Structural model facts compile without application sources or compiled contracts."""

import os
from pathlib import Path
import re
import shutil

import pytest

from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
MODEL_ROOTS = ("SqliteVerifier.SchemaExtension", "SqliteVerifier.SchemaPreservation",
               "SqliteVerifier.LiteralPreservation", "SqliteVerifier.ModelProjection",
               "VerifierConformance.Laws")
"""Mixed-file facts and conformance laws must have a structural import closure."""
APPLICATION_MODULES = {"SqliteVerifier.Contract", "SqliteVerifier.ContractProofs",
                       "SqliteVerifier.Library", "SqliteVerifier.NullableProjection"}
"""These modules supply logical contracts or application observations, not model facts."""
ALLOWED_EXTERNAL_IMPORT_ROOTS = {"Init", "Std"}
"""The core model uses foundational libraries without the Lean compiler API."""
PROJECT_MODULE_PREFIXES = ("SqliteVerifier.", "VerifierConformance.")
"""Follow current local model modules until the package namespace migration replaces their paths."""
pytestmark = [pytest.mark.integration, pytest.mark.requires_lean("compiler")]


def model_closure() -> list[str]:
    """Order actual imports for compilation and reject application or Lean dependencies."""
    ordered: list[str] = []
    active: set[str] = set()

    def visit(module: str) -> None:
        """Follow source imports once and fail on a cycle instead of truncating the closure."""
        assert module not in APPLICATION_MODULES, module
        if module in ordered:
            return
        assert module not in active, f"Model import cycle: {module}"
        active.add(module)
        source = ROOT / (module.replace(".", "/") + ".lean")
        for line in re.findall(r"(?m)^import (.+)$", source.read_text()):
            for dependency in line.split():
                if dependency.startswith(PROJECT_MODULE_PREFIXES):
                    visit(dependency)
                else:
                    assert dependency.split(".")[0] in ALLOWED_EXTERNAL_IMPORT_ROOTS, (module, dependency)
        active.remove(module)
        ordered.append(module)

    for module in MODEL_ROOTS:
        visit(module)
    return ordered


@pytest.fixture(scope="module")
def isolated_model(tmp_path_factory: pytest.TempPathFactory,
                   lean_sysroot: Path) -> Path:
    """Compile copied model sources with only their own artifacts and the pinned sysroot."""
    directory = tmp_path_factory.mktemp("model-ownership") / "model"
    directory.mkdir()
    environment = {**os.environ, "LEAN_PATH": str(directory), "LEAN_SRC_PATH": str(directory)}
    for module in model_closure():
        relative = Path(module.replace(".", "/") + ".lean")
        source = directory / relative
        source.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, source)
        result = run_command([str(lean_sysroot / "bin/lean"), "-o", str(source.with_suffix(".olean")),
                              str(source)], cwd=directory, environment=environment, timeout=30)
        assert result.returncode == 0, result.diagnostic()
    return directory


def test_neutral_consumer_uses_structural_facts(isolated_model: Path,
                                              lean_sysroot: Path) -> None:
    """Lookup, updates, projections and conformance laws remain usable without a logical contract."""
    source = isolated_model / "Consumer.lean"
    source.write_text("\n".join(f"import {module}" for module in MODEL_ROOTS) + "\n" +
        "#check SqliteVerifier.Conforms.set\n#check SqliteVerifier.Database.set_comm\n"
        "#check SqliteVerifier.TableExtends.project\n#check SqliteVerifier.Schema.lookupProperties\n"
        "#check SqliteVerifier.Table.project_newNullable\n"
        "#check SqliteVerifier.Conformance.statement_atomicity\n")
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)], cwd=isolated_model,
        environment={**os.environ, "LEAN_PATH": str(isolated_model), "LEAN_SRC_PATH": str(isolated_model)},
        timeout=15)
    assert result.returncode == 0, result.diagnostic()


def test_application_import_is_refused_with_adjacent_checkout(
        isolated_model: Path, lean_sysroot: Path, lean_library: Path) -> None:
    """Nearby real application source and artifacts cannot satisfy a forbidden model dependency."""
    adjacent = isolated_model.parent / "application/SqliteVerifier"
    adjacent.mkdir(parents=True)
    shutil.copyfile(ROOT / "SqliteVerifier/Contract.lean", adjacent / "Contract.lean")
    shutil.copyfile(lean_library / "SqliteVerifier/Contract.olean", adjacent / "Contract.olean")
    source = isolated_model / "Forbidden.lean"
    source.write_text("import SqliteVerifier.Contract\n")
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)], cwd=isolated_model,
        environment={**os.environ, "LEAN_PATH": str(isolated_model), "LEAN_SRC_PATH": str(isolated_model)},
        timeout=15)
    assert result.returncode != 0 and "Contract" in result.stdout + result.stderr, result.diagnostic()
