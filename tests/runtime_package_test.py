"""Independently selectable acceptance checks through the actual installed native runtime."""

from collections.abc import Callable
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.packaging, pytest.mark.requires_nix,
              pytest.mark.requires_native, pytest.mark.requires_lean, pytest.mark.requires_sandbox]


@pytest.fixture(autouse=True)
def require_installed_variant(pytestconfig: pytest.Config) -> None:
    """Never let checkout binaries masquerade as installed-package acceptance."""
    if pytestconfig.getoption("runtime_variant") != "installed":
        pytest.fail("Installed acceptance requires --runtime-variant installed and an installed root or archive")


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_installed_parser(version: str, runtime_root: Path, tmp_path: Path,
                          command_runner: Callable[..., CommandResult]) -> None:
    """Both installed parsers retain their exact SQLite profiles under poisoned ambient imports."""
    parser = "sqlite-parser" if version == "3.51.0" else "sqlite-parser-3.46.0"
    result = command_runner([str(runtime_root / "build" / parser),
                             str(runtime_root / "examples/approved/schema.sql")], cwd=tmp_path, timeout=10)
    assert result.returncode == 0, result.diagnostic()
    assert result.json_object()["profile"] == version, result.diagnostic()


@pytest.fixture
def installed_verify(runtime_root: Path, tmp_path: Path,
                     command_runner: Callable[..., CommandResult]) -> Callable[..., CommandResult]:
    """Bind installed examples and launcher together without importing checkout implementation."""
    def invoke(candidate: str, *, migration: Path | None = None, timeout: int = 180) -> CommandResult:
        """Use the original public seven inputs and retain the installed test deadlines."""
        approved = runtime_root / "examples/approved"
        proposed = runtime_root / "examples" / candidate
        return command_runner([str(runtime_root / "bin/migration-check"), "verify", "--profile", "3.51.0",
            "--format", "json", "--schema", str(approved / "schema.sql"),
            "--requirements", str(approved / "Requirements.lean"),
            "--interpretation", str(approved / "Interpretation.lean"),
            "--migration", str(migration or proposed / "migration.sql"),
            "--next-interpretation", str(proposed / "NextInterpretation.lean"),
            "--proofs", str(proposed / "Proofs.lean")], cwd=tmp_path, timeout=timeout)
    return invoke


def test_verified_example(installed_verify: Callable[..., CommandResult]) -> None:
    """The installed entrypoint independently verifies the shipped positive migration."""
    result = installed_verify("add_column_then_table")
    assert result.returncode == 0 and result.json_object()["status"] == "VERIFIED", result.diagnostic()


def test_refuted_example(installed_verify: Callable[..., CommandResult]) -> None:
    """The installed entrypoint returns VIOLATED and nonzero for a kernel-checked refutation."""
    result = installed_verify("missing_required_column")
    assert result.returncode != 0 and result.json_object()["status"] == "VIOLATED", result.diagnostic()


def test_unsupported_migration(installed_verify: Callable[..., CommandResult], tmp_path: Path) -> None:
    """The installed entrypoint rejects unsupported DROP TABLE before proof acceptance."""
    migration = tmp_path / "unsupported.sql"
    migration.write_text("DROP TABLE invoices;\n")
    result = installed_verify("missing_required_column", migration=migration, timeout=30)
    assert result.returncode != 0 and result.json_object()["status"] == "UNSUPPORTED", result.diagnostic()


def test_installed_gc_roots(runtime_root: Path) -> None:
    """Installation retains its Nix dependency roots for offline runtime use."""
    assert (runtime_root / ".nix-roots").is_dir()
