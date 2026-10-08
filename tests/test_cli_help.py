"""The public CLI explains contract-input roles and points readers to the checked API guide."""

from pathlib import Path
import subprocess
import sys

import pytest

from migration_check.cli import API_REFERENCE_GUIDE, arguments

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.parametrize("command", [None, "verify", "prepare", "verify-bundle"])
def test_public_help_links_the_reference_and_explains_input_roles(command: str | None) -> None:
    """The real source entrypoint prints useful help before it needs any runtime or proof inputs."""
    values = [] if command is None else [command]
    result = subprocess.run([sys.executable, str(ROOT / "bin/migration-check"), *values, "--help"],
                            cwd=ROOT, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    output = " ".join(result.stdout.split())
    assert API_REFERENCE_GUIDE in output
    if command is not None:
        assert "Approved Lean logical contract" in output
        assert "Approved Lean meaning and admission condition" in output
        assert "Candidate migration SQL" in output
    if command in {"verify", "verify-bundle"}:
        assert "every model-conforming starting database" in output
    if command == "verify-bundle":
        assert "resulting/failure interpretations and proofs" in output
    elif command is not None:
        assert "proof or refutation" in output


@pytest.mark.parametrize("command", ["verify", "prepare", "verify-bundle"])
def test_help_prose_preserves_required_paths_and_defaults(command: str) -> None:
    """Documentation changes preserve the argument contract used by verification and preparation callers."""
    values = [command, "--profile", "3.51.0"]
    names = ["schema", "requirements", "interpretation", "migration"]
    names += ["bundle"] if command == "verify-bundle" else ["next-interpretation", "proofs"]
    names += ["workspace", "output"] if command == "prepare" else []
    for name in names:
        values += ["--" + name, name + ".input"]
    parsed = arguments(values)
    assert parsed.command == command and parsed.profile == "3.51.0"
    assert parsed.format == "human"
    assert all(getattr(parsed, name.replace("-", "_")) == Path(name + ".input") for name in names)
    if command != "prepare":
        assert parsed.approved_baseline is None
