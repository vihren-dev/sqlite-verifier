"""The pinned Lean compiler checks public documentation terms and error locations."""

import os
from pathlib import Path

import pytest

from tests.runtime_support import run_command

pytestmark = [pytest.mark.integration, pytest.mark.requires_lean("compiler")]


@pytest.mark.parametrize(("documentation", "accepted"), [
    ("Use {name}`SqliteVerifier.Column`. "
     '{assert}`SqliteVerifier.Column.plain { name := "id", affinity := .integer } = true`.', True),
    ("Use {name}`SqliteVerifier.notADeclaration`.", False),
    ('Use {lean}`Nat.succ "wrong"`.', False),
    ('{assert}`SqliteVerifier.Column.plain { name := "id", affinity := .integer } = false`.', False),
])
def test_documentation_checks_terms_and_reports_the_source_location(
        documentation: str, accepted: bool, tmp_path: Path,
        lean_sysroot: Path, lean_library: Path) -> None:
    """Real compilation accepts the true example and refuses three distinct documentation defects."""
    source = tmp_path / "DocumentationProbe.lean"
    source.write_text("import SqliteVerifier\nset_option doc.verso true\n\n"
                      f"/-- {documentation} -/\ndef documentationProbe : Nat := 0\n")
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)],
        cwd=tmp_path, timeout=15, environment={**os.environ, "LEAN_PATH": str(lean_library)})
    if accepted:
        assert result.returncode == 0, result.diagnostic()
    else:
        assert result.returncode != 0, result.diagnostic()
        assert f"{source}:4:" in result.stdout + result.stderr, result.diagnostic()
