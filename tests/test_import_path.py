"""Split package views preserve the ordered trusted-file boundary and clean up after use."""

from collections.abc import Iterator
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


@pytest.mark.parametrize("insensitive_roots", [{"library", "candidate"}, {"library"}, {"candidate"}, set()],
                         ids=["equivalent", "candidate-sensitive", "trusted-sensitive", "sensitive"])
@pytest.mark.parametrize("candidate_name", ["Model", "model"])
def test_views_preserve_each_original_spelling(tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch, insensitive_roots: set[str], candidate_name: str) -> None:
    """Mixed volumes retain the first resolving origin and each spelling's missing siblings."""
    library, candidate = tmp_path / "library", tmp_path / "candidate"
    core = artifact(library, "Model/Core.olean", "trusted-core")
    replacement = artifact(candidate, f"{candidate_name}/Core.olean", "candidate-core")
    sibling = artifact(candidate, f"{candidate_name}/User.olean", "candidate-sibling")
    canonical = {library: "Model", candidate: candidate_name}

    def original_lookup(root: Path, spelling: str) -> Path | None:
        """Model each original volume independently of the host's filesystem."""
        name = canonical[root]
        if spelling == name or (root.name in insensitive_roots and spelling.casefold() == name.casefold()):
            return root / name
        return None

    monkeypatch.setattr(import_path, "package_directory", original_lookup)
    for roots in ((library, candidate), (candidate, library)):
        views = {name: import_path.package_view(roots, name, ()) for name in ("Model", "model", "mODEL")}
        for spelling, view in views.items():
            resolving = [root for root in roots if original_lookup(root, spelling) is not None]
            if resolving:
                expected = core if resolving[0] == library else replacement
                assert view[Path(spelling) / "Core.olean"].samefile(expected)
            else:
                assert not view
            supplied = original_lookup(candidate, spelling) is not None
            assert (Path(spelling) / "User.olean" in view) == supplied
            if supplied:
                assert view[Path(spelling) / "User.olean"].samefile(sibling)
        import_path.compatible_views(views, ignores_case=False)
        if insensitive_roots == {"library", "candidate"} or (
                roots[0] == candidate and "candidate" in insensitive_roots):
            import_path.compatible_views(views, ignores_case=True)
        else:
            with pytest.raises(ValueError, match="case-sensitive workspace"):
                import_path.compatible_views(views, ignores_case=True)


@pytest.mark.parametrize("difference", ["origin", "missing-sibling"])
def test_workspace_rejects_distinct_views(tmp_path: Path, difference: str) -> None:
    """An insensitive workspace cannot silently replace an origin or expose a missing sibling."""
    trusted = artifact(tmp_path / "library", "Core.olean", "trusted")
    candidate = artifact(tmp_path / "candidate", "Core.olean", "candidate")
    views = {"Model": {Path("Model/Core.olean"): trusted}, "model": {}}
    if difference == "origin":
        views["model"][Path("model/Core.olean")] = candidate
    import_path.compatible_views(views, ignores_case=False)
    with pytest.raises(ValueError, match="case-sensitive workspace"):
        import_path.compatible_views(views, ignores_case=True)


@pytest.mark.parametrize("requested", [Path("/absolute"), Path("../escape"), Path("Model/../escape"), Path(".")])
def test_requested_module_cannot_escape_roots(tmp_path: Path, requested: Path) -> None:
    """Invalid requested paths fail before any workspace is created."""
    with pytest.raises(ValueError, match="relative Lean module path") as error:
        with merged_search_path([], tmp_path, requested=[requested]):
            pytest.fail("Unsafe module path was accepted")
    assert repr(str(requested)) in str(error.value)
    assert "with no '.' or '..' parts" in str(error.value)


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


def test_requested_module_keeps_all_companion_artifacts(tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch) -> None:
    """package_view resolves explicit module spellings absent from the enumerated names."""
    root = tmp_path / "library"
    files = {suffix: artifact(root, "Model/Alias" + suffix, suffix)
             for suffix in (".olean", ".olean.server", ".olean.private", ".ir", ".ir.sig")}

    def enumerated_names(directory: Path, pattern: str) -> Iterator[Path]:
        """Stand in for physical-name enumeration that cannot list every lookup alias."""
        return iter(())

    monkeypatch.setattr(Path, "rglob", enumerated_names)
    assert import_path.package_view([root], "Model", ()) == {}
    view = import_path.package_view([root], "Model", [Path("Model/Alias")])
    assert set(view) == {Path("Model/Alias" + suffix) for suffix in files}
    for suffix, source in files.items():
        assert view[Path("Model/Alias" + suffix)].samefile(source)


def test_link_collision_preserves_origins_or_requires_sensitive_workspace(tmp_path: Path) -> None:
    """compatible_links retains distinct sensitive paths and refuses an insensitive origin collision."""
    first = artifact(tmp_path / "first", "Core.olean", "first")
    second = artifact(tmp_path / "second", "Core.olean", "second")
    links = {Path("Model/Core.olean"): first, Path("model/core.olean"): second}
    assert import_path.compatible_links(links, ignores_case=False) == links
    with pytest.raises(ValueError, match="case-sensitive workspace"):
        import_path.compatible_links(links, ignores_case=True)


def test_identical_link_origins_can_share_an_insensitive_path(tmp_path: Path) -> None:
    """compatible_links combines case aliases only when their selected file origins are identical."""
    source = artifact(tmp_path, "Core.olean", "same")
    links = {Path("Model/Core.olean"): source, Path("model/core.olean"): source}
    assert import_path.compatible_links(links, ignores_case=True) == {Path("Model/Core.olean"): source}
