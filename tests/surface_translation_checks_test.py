"""The checks of the text package's translation (`packages/belay-sqlite-text/Belay/Sqlite/Translation`)
that need its Lean values: the ranges of model paths and the lexical helpers
(`tests/surface/TranslationChecks.lean`). The other checks of the translation go through its
program (`tests/syntax_*_test.py`).
"""

from pathlib import Path

import pytest

from tests.runtime_support import run_command
from tests.surface_support import FIXTURES, surface_command

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_lean("compiler")]


def test_translation_checks_elaborate(runtime_root: Path, tmp_path: Path) -> None:
    """The fixture's checks hold: a model path selects the range of its node, also in a subquery,
    in a compound SELECT and past a leaf; `dequote` follows SQLite; `valueRows` refuses a
    malformed VALUES node with the modeled forms; `decodeParse` refuses a document for another
    grammar."""
    result = run_command(surface_command(runtime_root, FIXTURES / "TranslationChecks.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()
