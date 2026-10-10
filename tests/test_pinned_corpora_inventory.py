"""Check that `conformance/pinned-corpora.json` names every frozen corpus.

The `pinned` Nix suite sees only the pinned directories, so it cannot find a new
frozen corpus that has no pin. This host check reads the repository instead.
"""

import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.unit, pytest.mark.conformance]


def test_each_frozen_corpus_directory_is_pinned() -> None:
    """Each `conformance/corpus-v*` directory and the synthetic workload corpus has a pin."""
    pins = json.loads((ROOT / "conformance/pinned-corpora.json").read_text())
    frozen = {path.relative_to(ROOT).as_posix() for path in (ROOT / "conformance").glob("corpus-v*")}
    assert frozen | {"conformance/synthetic-workload/corpus"} == set(pins.values())
    assert all((ROOT / directory / "manifest.json").is_file() for directory in pins.values())
