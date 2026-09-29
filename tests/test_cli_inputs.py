"""Check fast user-facing input diagnostics before any proof process can run."""

import json
from pathlib import Path

import pytest

from migration_check.cli import main

pytestmark = pytest.mark.unit


@pytest.mark.parametrize("suffix,status", [([], "INPUT_ERROR"), (["--profile", "latest"], "INPUT_ERROR"),
                                           (["--profile", "3.50.0"], "UNSUPPORTED")],
                         ids=["missing", "malformed", "unsupported"])
def test_profile_diagnostics(capsys: pytest.CaptureFixture[str], suffix: list[str], status: str) -> None:
    """Invalid profiles fail consistently without requiring source files or installed artifacts."""
    command = ["verify", "--format", "json"]
    for name in ("schema", "interpretation", "migration", "next-interpretation", "requirements", "proofs"):
        command.extend(["--" + name, str(Path("missing") / name)])
    assert main([*command, *suffix]) == 1
    assert json.loads(capsys.readouterr().out)["status"] == status
