"""Check pinned tool identities and native schema behavior as independent cases."""

from pathlib import Path
import subprocess

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.environment]


def run(*arguments: str) -> str:
    """Bound every external check and retain stderr when a tool fails."""
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, (arguments, result.returncode, result.stdout, result.stderr)
    return result.stdout.strip()


@pytest.mark.requires_lean("compiler")
def test_lean_version(lean_sysroot: Path) -> None:
    """Lean reports the exact release pinned by the source toolchain file."""
    version = (Path(__file__).resolve().parents[1] / "lean-toolchain").read_text().strip().split(":v")[1]
    assert f"version {version}," in run(str(lean_sysroot / "bin/lean"), "--version")


@pytest.mark.requires_lean("compiler")
def test_lake_version(lean_sysroot: Path) -> None:
    """Lake belongs to the same pinned release as Lean."""
    version = (Path(__file__).resolve().parents[1] / "lean-toolchain").read_text().strip().split(":v")[1]
    assert version in run(str(lean_sysroot / "bin/lake"), "--version")


@pytest.mark.requires_native("sqlite3")
def test_sqlite_351_identity() -> None:
    """The native current SQLite has the reviewed version and source identity."""
    assert run("sqlite3", ":memory:", "SELECT sqlite_version();") == "3.51.0"
    assert run("sqlite3", ":memory:", "SELECT sqlite_source_id();") == (
        "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b")


@pytest.mark.requires_native("sqlite3-3.46.0")
def test_sqlite_346_identity() -> None:
    """The older native SQLite has its own reviewed version and source identity."""
    assert run("sqlite3-3.46.0", ":memory:", "SELECT sqlite_version();") == "3.46.0"
    assert run("sqlite3-3.46.0", ":memory:", "SELECT sqlite_source_id();") == (
        "2024-05-23 13:25:27 96c92aba00c8375bc32fafcdf12429c58bd8aabfcadab6683e35bbb9cdebf19e")
