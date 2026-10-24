"""Check the schema metadata law and its SQL observations through the surface fixture."""

from pathlib import Path

import pytest

from tests.runtime_support import run_command
from tests.surface_support import FIXTURES, surface_command

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_lean("compiler")]


def test_pragma_metadata_matches_catalog_columns(runtime_root: Path, tmp_path: Path) -> None:
    """`TableInfoLaws.lean` preserves declared types, NOT NULL flags and primary-key positions, and omits generated
    columns; `ClaimsTableInfoMetadata.lean` checks its positive and negative cases and the corresponding SQL outputs."""
    result = run_command(surface_command(runtime_root, FIXTURES / "ClaimsTableInfoMetadata.lean", tmp_path),
                         cwd=tmp_path, timeout=60)
    assert result.returncode == 0, result.diagnostic()
