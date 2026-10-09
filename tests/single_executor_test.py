"""The compiled library exposes one SQL executor and rejects every retired proof API."""

import os
from pathlib import Path
import subprocess

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean]


@pytest.mark.parametrize("name", ["run", "runFrom", "Executes", "runFrom_executes",
    "runFrom_append", "Statement.isExtension", "VerificationConditions.of_run",
    "VerificationConditions.congr_run"])
def test_retired_execution_declarations(name: str, lean_sysroot: Path, lean_libraries: tuple[Path, Path],
                                        tmp_path: Path) -> None:
    """A caller cannot use a removed declaration through the installed public import."""
    source = tmp_path / "Removed.lean"
    source.write_text(f"import SqliteVerifier\n#check SqliteVerifier.{name}\n")
    result = subprocess.run([str(lean_sysroot / "bin/lean"), str(source)],
        env={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_libraries))}, capture_output=True, text=True, timeout=10)
    assert result.returncode != 0 and "error(lean.unknownIdentifier)" in result.stdout, result.stdout + result.stderr
    assert f"SqliteVerifier.{name}" in result.stdout, result.stdout + result.stderr


def test_retired_bridge_import(lean_sysroot: Path, lean_libraries: tuple[Path, Path], tmp_path: Path) -> None:
    """The runtime contains no compiled compatibility bridge for the removed executor."""
    source = tmp_path / "RemovedBridge.lean"
    source.write_text("import SqliteVerifier.ExtensionExecution\n")
    result = subprocess.run([str(lean_sysroot / "bin/lean"), str(source)],
        env={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_libraries))}, capture_output=True, text=True, timeout=10)
    diagnostic = result.stdout + result.stderr
    assert result.returncode != 0 and "SqliteVerifier.ExtensionExecution" in diagnostic, diagnostic
    assert "does not exist" in diagnostic, diagnostic
