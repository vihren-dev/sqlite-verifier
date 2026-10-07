"""Changing transition documentation cannot break the production mutation harness."""

from pathlib import Path
import re

import pytest

from conformance.mutation_check import schema_step_source

EXECUTION = Path(__file__).resolve().parents[1] / "SqliteVerifier/Execution.lean"


@pytest.mark.parametrize("documentation", ["", "/-- Replacement documentation. -/"])
def test_step_shadow_ignores_documentation(documentation: str) -> None:
    """The actual transition remains identical when every declaration docstring changes."""
    original = EXECUTION.read_text()
    changed = re.sub(r"/--.*?-/", documentation, original, flags=re.DOTALL)
    assert changed != original
    assert schema_step_source(changed) == schema_step_source(original)


@pytest.mark.parametrize("boundary", ["\ndef step ", "\nend SqliteVerifier"])
def test_step_shadow_requires_code_boundaries(boundary: str) -> None:
    """A missing declaration or namespace closure fails before a partial model is compiled."""
    with pytest.raises(ValueError):
        schema_step_source(EXECUTION.read_text().replace(boundary, "\nmissing boundary "))
