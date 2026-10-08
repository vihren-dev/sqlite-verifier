"""Split package views preserve the ordered trusted-file boundary and clean up after use."""

from pathlib import Path

import pytest

from migration_check import import_path
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
    model = tmp_path / "model"
    model.mkdir()
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
    model = tmp_path / "model"
    model.mkdir()
    artifact(library, "Model/Core.olean", "trusted")
    artifact(candidate, "Application/User.olean", "candidate")
    before = set(tmp_path.iterdir())
    with merged_search_path([library, candidate], tmp_path) as paths:
        assert paths == (library, candidate)
    assert set(tmp_path.iterdir()) == before


def test_package_case_follows_filesystem_without_changing_precedence(tmp_path: Path) -> None:
    """Case aliases merge on macOS volumes; distinct packages retain their roots on sensitive volumes."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    artifact(library, "Model/Core.olean", "trusted-core")
    artifact(library, "Model.olean", "trusted-base")
    artifact(candidate, "model/Core.olean", "candidate-substitution")
    artifact(candidate, "model.olean", "candidate-base-substitution")
    artifact(candidate, "model/User.olean", "candidate-sibling")
    with merged_search_path([library, candidate], tmp_path) as paths:
        if (library / "model").exists():
            assert paths[1:] == (library, candidate)
            assert (paths[0] / "model/Core.olean").read_text() == "trusted-core"
            assert (paths[0] / "model.olean").read_text() == "trusted-base"
            assert (paths[0] / "model/User.olean").read_text() == "candidate-sibling"
        else:
            assert paths == (library, candidate)
            assert (candidate / "model/Core.olean").read_text() == "candidate-substitution"


@pytest.mark.parametrize("insensitive_roots", [{"library", "candidate"}, {"library"}, {"candidate"}],
                         ids=["equivalent", "candidate-sensitive", "trusted-sensitive"])
@pytest.mark.parametrize("candidate_name", ["Model", "model"])
def test_original_root_case_modes_control_alias_merging(tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch, insensitive_roots: set[str], candidate_name: str) -> None:
    """Equivalent roots expose aliases; matching spellings retain siblings even across mixed volumes."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    artifact(library, "Model/Core.olean", "trusted-core")
    artifact(candidate, f"{candidate_name}/Core.olean", "candidate-substitution")
    artifact(candidate, f"{candidate_name}/User.olean", "candidate-sibling")
    def root_ignores_case(directory: Path) -> bool:
        """Supply explicit original-volume case modes independently of the test host."""
        return directory.parent.name in insensitive_roots

    monkeypatch.setattr(import_path, "ignores_package_case", root_ignores_case)
    for roots in ((library, candidate), (candidate, library)):
        with merged_search_path(roots, tmp_path) as paths:
            if insensitive_roots == {"library", "candidate"} or candidate_name == "Model":
                assert paths[1:] == roots
                assert (paths[0] / "Model").samefile(paths[0] / candidate_name)
                expected = "trusted-core" if roots[0] == library else "candidate-substitution"
                assert (paths[0] / f"{candidate_name}/Core.olean").read_text() == expected
                assert (paths[0] / f"{candidate_name}/User.olean").read_text() == "candidate-sibling"
            else:
                assert paths == roots


@pytest.mark.integration
@pytest.mark.requires_lean("compiler")
def test_real_lean_keeps_trusted_definition_in_split_package(tmp_path: Path, lean_sysroot: Path) -> None:
    """A sibling theorem compiles against the first root's value despite a conflicting candidate module."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    model = tmp_path / "model"
    model.mkdir()
    for directory, value in ((library, 7), (candidate, 99)):
        source = artifact(directory, "Model/Core.lean", f"def Model.value : Nat := {value}\n")
        lean_process(lean_sysroot, (directory, model), [], source, directory,
            ["-R", str(directory), "-o", str(source.with_suffix(".olean"))], "fixture", timeout=10)
    source = artifact(candidate, "Model/User.lean", "import Model.Core\nexample : Model.value = 7 := rfl\n")
    lean_process(lean_sysroot, (library, model), [candidate], source, candidate,
        ["-R", str(candidate), "-o", str(source.with_suffix(".olean"))], "collision", timeout=10)
    assert source.with_suffix(".olean").is_file()
