"""Check that users can identify and replace an incompatible Lean installation."""

from pathlib import Path
import sys

import pytest

from migration_check.diagnostics import Rejection
from migration_check.runtime import Runtime


def test_wrong_version_identifies_runtime_and_remedy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Run the configured executable so its actual version appears in the rejection."""
    sysroot = tmp_path / "other-lean"
    executable = sysroot / "bin/lean"
    executable.parent.mkdir(parents=True)
    detected = "Lean (version 4.30.0, x86_64-unknown-linux-gnu, commit old)"
    executable.write_text(f"#!{sys.executable}\nprint({detected!r})\n", encoding="utf-8")
    executable.chmod(0o755)
    monkeypatch.setenv("MIGRATION_CHECK_LEAN_SYSROOT", str(sysroot))

    with pytest.raises(Rejection) as rejected:
        Runtime.locate()

    assert rejected.value.status == "INPUT_ERROR"
    message = str(rejected.value)
    assert str(sysroot.resolve()) in message
    assert detected in message
    assert "requires Lean 4.34.1" in message
    assert "Set MIGRATION_CHECK_LEAN_SYSROOT" in message
    assert "reinstall the verifier" in message
