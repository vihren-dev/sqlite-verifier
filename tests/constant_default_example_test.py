"""Reject a changed default through source verification and the independent bundle gate."""

from collections.abc import Callable
from pathlib import Path

import pytest

from migration_check.project_config import load
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.kernel, pytest.mark.requires_lean,
              pytest.mark.requires_native]


def test_changed_default_rejects_original_certificate(runtime_root: Path,
        example_factory: Callable[[str], Path], tmp_path: Path,
        command_runner: Callable[..., CommandResult]) -> None:
    """The public gates reject DEFAULT 8 when the contract and certificate require DEFAULT 7."""
    example = example_factory("constant_default")
    case = load(example / "belay.toml", example)
    launcher = str(runtime_root / "bin/migration-check")
    bundle = tmp_path / "proof.bundle"
    prepared = command_runner([launcher, "prepare", "--format", "json",
        *case.contract_arguments(), "--project", str(case.proofs), "--output", str(bundle),
        "--cache", str(tmp_path / "author-cache")], cwd=tmp_path, timeout=240)
    assert prepared.returncode == 0 and prepared.json_object()["status"] == "PREPARED", prepared.diagnostic()
    original = case.migration.read_text()
    changed = original.replace("DEFAULT 7", "DEFAULT 8")
    assert changed != original
    case.migration.write_text(changed)
    source = command_runner([launcher, "verify", "--format", "json",
        *case.contract_arguments(), *case.candidate_arguments(),
        "--approved-baseline", str(case.baseline)], cwd=tmp_path, timeout=120)
    assert source.returncode == 1 and source.json_object()["status"] == "UNVERIFIED", source.diagnostic()
    checked = command_runner([launcher, "verify-bundle", "--format", "json",
        *case.contract_arguments(), "--bundle", str(bundle), "--no-cache"], cwd=tmp_path, timeout=240)
    assert checked.returncode == 1 and checked.json_object()["status"] == "UNVERIFIED", checked.diagnostic()
