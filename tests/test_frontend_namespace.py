"""The `belay.sqlite` frontend is one namespace portion that does not import the verification application.

This check runs on the host, on the complete checkout. In a Nix suite it would see only the frontend
modules listed in `tests/conformance_frontend.json`, so it could not check a module that is missing
from that list.
"""

import ast
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / "belay/sqlite"
pytestmark = [pytest.mark.unit]


def test_namespace_and_independent_imports() -> None:
    """The namespace contains one portion and no frontend source depends on application code."""
    assert not (ROOT / "belay/__init__.py").exists()
    assert {path.name for path in (ROOT / "belay").iterdir()} == {"sqlite"}
    sources = sorted(FRONTEND.glob("*.py"))
    assert sources, f"No frontend sources found in {FRONTEND}"
    for path in sources:
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if isinstance(node, ast.ImportFrom):
                assert not (node.module or "").startswith("migration_check"), path
            elif isinstance(node, ast.Import):
                assert not any(alias.name.startswith("migration_check") for alias in node.names), path
    assert not list((ROOT / "migration_check").glob("sql_*.py"))
