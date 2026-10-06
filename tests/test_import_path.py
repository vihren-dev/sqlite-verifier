"""Split package views preserve the ordered trusted-file boundary and clean up after use."""

from pathlib import Path

import pytest

from migration_check.import_path import merged_search_path
from migration_check.source_closure import lean_process


def artifact(root: Path, relative: str, contents: str) -> Path:
    """Retain distinct candidate and trusted bytes at the same relative artifact identity."""
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
    return path


def test_split_package_keeps_trusted_precedence_and_candidate_siblings(tmp_path: Path) -> None:
    """A candidate collision cannot replace the first root, while its distinct sibling remains reachable."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    trusted = artifact(library, "Model/Core.olean", "trusted-core")
    base = artifact(library, "Model.olean", "trusted-base")
    artifact(candidate, "Model/Core.olean", "candidate-substitution")
    artifact(candidate, "Model.olean", "candidate-base-substitution")
    sibling = artifact(candidate, "Model/User.olean", "candidate-sibling")
    with merged_search_path([library, candidate], tmp_path) as paths:
        merged = paths[0]
        assert paths[1:] == (library, candidate)
        assert (merged / "Model/Core.olean").read_bytes() == trusted.read_bytes()
        assert (merged / "Model.olean").read_bytes() == base.read_bytes()
        assert (merged / "Model/User.olean").read_bytes() == sibling.read_bytes()
        assert trusted.read_text() == "trusted-core" and base.read_text() == "trusted-base"
    assert not merged.exists()
    with merged_search_path([candidate, library], tmp_path) as paths:
        assert (paths[0] / "Model/Core.olean").read_text() == "candidate-substitution"


def test_distinct_packages_need_no_merged_directory(tmp_path: Path) -> None:
    """Unsplit roots preserve their original search path and allocate no overlay."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    artifact(library, "Model/Core.olean", "trusted")
    artifact(candidate, "Application/User.olean", "candidate")
    before = set(tmp_path.iterdir())
    with merged_search_path([library, candidate], tmp_path) as paths:
        assert paths == (library, candidate)
    assert set(tmp_path.iterdir()) == before


@pytest.mark.integration
@pytest.mark.requires_lean("compiler")
def test_real_lean_keeps_trusted_definition_in_split_package(tmp_path: Path, lean_sysroot: Path) -> None:
    """A sibling theorem compiles against the first root's value despite a conflicting candidate module."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    for directory, value in ((library, 7), (candidate, 99)):
        source = artifact(directory, "Model/Core.lean", f"def Model.value : Nat := {value}\n")
        lean_process(lean_sysroot, directory, [], source, directory,
            ["-R", str(directory), "-o", str(source.with_suffix(".olean"))], "fixture", timeout=10)
    source = artifact(candidate, "Model/User.lean", "import Model.Core\nexample : Model.value = 7 := rfl\n")
    lean_process(lean_sysroot, library, [candidate], source, candidate,
        ["-R", str(candidate), "-o", str(source.with_suffix(".olean"))], "collision", timeout=10)
    assert source.with_suffix(".olean").is_file()
