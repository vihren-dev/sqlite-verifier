"""Our code in the API reference build: doc-gen4 arguments, recursor correction, commit links.

These tests check what we give to doc-gen4 and what we change in its output, not doc-gen4
itself (see "Testing" in AGENTS.md and ADR 0009).
"""

import json
from pathlib import Path
import re
import subprocess

import pytest

import tools.api_reference as api_reference
from tools.api_reference import (CORE_DATABASE, SOURCE_REPOSITORY, SOURCE_REVISION_PLACEHOLDER,
                                  correct_recursor_links, generate_reference)
from tools.api_reference_links import link_sources
from tools.ci_store_gc import TARGETS
from tools.source_revision import FULL_COMMIT_HASH_PATTERN

pytestmark = [pytest.mark.unit, pytest.mark.environment]
REVISION = "1234567890abcdef1234567890abcdef12345678"
"""A complete source identity used by the isolated reference fixture."""
BUILD_SUPPORT = Path(__file__).resolve().parents[1] / "build-support"


def test_nix_and_python_source_revision_policy_agree() -> None:
    """Both build-boundary checks enforce the same full-commit requirement."""
    match = re.search(r'fullCommitHashPattern = "([^"]+)";', (BUILD_SUPPORT / "api-reference-links.nix").read_text())
    assert match is not None
    assert match.group(1) == FULL_COMMIT_HASH_PATTERN


def test_core_takes_only_the_toolchain_and_doc_gen4() -> None:
    """No repository file reaches the core build, the base starts from it, and CI keeps both."""
    core = (BUILD_SUPPORT / "api-reference-core.nix").read_text()
    assert "{ pkgs, leanToolchain, docGen4 }:" in core and "../" not in core
    base = (BUILD_SUPPORT / "api-reference.nix").read_text()
    assert "{ pkgs, sources, leanToolchain, lean4export, docGen4, core, modelPackage }:" in base
    assert "--revision" not in base and "inventory" not in base
    assert {"apiReferenceCore", "apiReferenceBase"} <= set(TARGETS)


def pages(output: Path, ours: str, core: str = "<p id=\"List\"></p>") -> None:
    """One page of ours with a model type, and one Lean library page with `List`."""
    (output / "SqliteVerifier").mkdir(parents=True)
    (output / "Init").mkdir()
    (output / "SqliteVerifier/Model.html").write_text('<a id="Value"></a>' + ours)
    (output / "Init/Data.html").write_text(core)


def test_correction_points_recursors_on_our_pages_at_their_type(tmp_path: Path) -> None:
    """Links to omitted recursors, also into Lean's pages, get the parent anchor; Lean's pages stay."""
    lean_page = '<p id="List"></p><a href="#List.casesOn">core</a>'
    pages(tmp_path, '<a href="#Value.rec">own</a><a href="../Init/Data.html#List.rec">list</a>', lean_page)
    assert correct_recursor_links(tmp_path) == 2
    ours = (tmp_path / "SqliteVerifier/Model.html").read_text()
    assert 'href="#Value"' in ours and 'href="../Init/Data.html#List"' in ours
    assert (tmp_path / "Init/Data.html").read_text() == lean_page
    assert correct_recursor_links(tmp_path) == 0


@pytest.mark.parametrize("link", ["#Value.other", "#Missing.rec", "#example%20.rec"])
def test_correction_changes_only_omitted_recursors(tmp_path: Path, link: str) -> None:
    """Other suffixes, a missing parent and an existing raw anchor keep the link unchanged."""
    page = f'<a id="example%20.rec"></a><a href="{link}">link</a>'
    pages(tmp_path, page)
    assert correct_recursor_links(tmp_path) == 0
    assert (tmp_path / "SqliteVerifier/Model.html").read_text() == '<a id="Value"></a>' + page


def source_tree(root: Path) -> Path:
    """An entry point and two nested library modules, without compiling Lean."""
    (root / "SqliteVerifier/Nested").mkdir(parents=True)
    for path in ("SqliteVerifier.lean", "SqliteVerifier/Model.lean", "SqliteVerifier/Nested/Rows.lean"):
        (root / path).write_text("-- fixture\n")
    return root


def run_generator(tmp_path: Path, ours: str) -> tuple[list[list[str]], Path]:
    """Run the generator with a stand-in for doc-gen4 that only records its arguments."""
    root, build, calls = source_tree(tmp_path / "source"), tmp_path / "build", []
    (build / CORE_DATABASE).parent.mkdir(parents=True)
    (build / CORE_DATABASE).write_text("core")
    pages(build / "doc", ours)

    def record(command: list[str], **options: object) -> subprocess.CompletedProcess[str]:
        """Accept every doc-gen4 call and keep its arguments."""
        assert options["cwd"] == root and options["check"] and options["timeout"]
        calls.append(command)
        return subprocess.CompletedProcess(command, 0)

    with pytest.MonkeyPatch.context() as patch:
        patch.setattr(api_reference.subprocess, "run", record)
        generate_reference(root, Path("/tools/doc-gen4"), build)
    return calls, build


def test_generator_gives_each_module_its_own_source_uri(tmp_path: Path) -> None:
    """Each public module is added once with its file's placeholder URI, before one `fromDb`."""
    calls, build = run_generator(tmp_path, '<a href="#Value.rec">own</a>')
    prefix = f"{SOURCE_REPOSITORY}/blob/{SOURCE_REVISION_PLACEHOLDER}/"
    modules = {"SqliteVerifier": "SqliteVerifier.lean", "SqliteVerifier.Model": "SqliteVerifier/Model.lean",
               "SqliteVerifier.Nested.Rows": "SqliteVerifier/Nested/Rows.lean"}
    assert all(call[:3] == ["lake", "env", "/tools/doc-gen4"] for call in calls)
    assert [call[3:] for call in calls[:-1]] == [
        ["single", "--build", str(build), module, CORE_DATABASE, prefix + path] for module, path in modules.items()]
    assert calls[-1][3:] == ["fromDb", "--build", str(build), "--manifest", str(build / "manifest.json"),
                             str(build / CORE_DATABASE), *modules]
    assert json.loads((build / "doc/reference-check.json").read_text()) == {"public_modules": 3, "corrected_links": 1}


def test_generator_reports_a_missing_core_or_a_fixed_doc_gen4_bug(tmp_path: Path) -> None:
    """A build without the core database fails; so does one with no recursor link to correct."""
    with pytest.raises(ValueError, match="build apiReferenceCore first"):
        generate_reference(source_tree(tmp_path / "source"), Path("/tools/doc-gen4"), tmp_path / "empty")
    with pytest.raises(ValueError, match="doc-gen4 may have fixed the bug"):
        run_generator(tmp_path / "fixed", "<p>no recursor link</p>")


def linked_base(root: Path, page: str) -> Path:
    """A base reference with one page and the report of the base build."""
    base = root / "base"
    (base / "SqliteVerifier").mkdir(parents=True)
    (base / "SqliteVerifier/Model.html").write_text(page)
    (base / "reference-check.json").write_text(json.dumps({"public_modules": 1}))
    return base


def placeholder_link(line: int) -> str:
    """One generated source link of the base build."""
    return f'<a href="{SOURCE_REPOSITORY}/blob/{SOURCE_REVISION_PLACEHOLDER}/SqliteVerifier/Model.lean#L{line}">source</a>'


def test_link_step_puts_the_commit_into_every_source_link(tmp_path: Path) -> None:
    """Each placeholder link names the commit, the base is unchanged and the report records both."""
    page = placeholder_link(1) + placeholder_link(2)
    base = linked_base(tmp_path, page)
    assert link_sources(base, tmp_path / "out", REVISION) == 2
    linked = (tmp_path / "out/SqliteVerifier/Model.html").read_text()
    assert linked.count(f"{SOURCE_REPOSITORY}/blob/{REVISION}/") == 2 and SOURCE_REVISION_PLACEHOLDER not in linked
    assert (base / "SqliteVerifier/Model.html").read_text() == page
    report = json.loads((tmp_path / "out/reference-check.json").read_text())
    assert report == {"public_modules": 1, "source_revision": REVISION, "source_links": 2}


@pytest.mark.parametrize("damage", ["revision", "stray", "foreign", "none"])
def test_link_step_refuses_unlinked_or_foreign_sources(tmp_path: Path, damage: str) -> None:
    """A branch name, a leftover placeholder, a link to another commit or no link fails."""
    page = {"revision": placeholder_link(1), "stray": placeholder_link(1) + SOURCE_REVISION_PLACEHOLDER,
            "foreign": placeholder_link(1) + f'<a href="{SOURCE_REPOSITORY}/blob/{"0" * 40}/x.lean">old</a>',
            "none": "<p>no source</p>"}[damage]
    base = linked_base(tmp_path, page)
    with pytest.raises(ValueError):
        link_sources(base, tmp_path / "out", "main" if damage == "revision" else REVISION)


def test_generator_maps_model_package_to_module_and_repository_uri(tmp_path: Path) -> None:
    """Our generator passes a model module name and its exact package source URI to doc-gen4."""
    model = tmp_path / "source/packages/belay-sqlite/Belay/Sqlite/Schema.lean"
    model.parent.mkdir(parents=True)
    model.write_text("-- fixture\n")
    calls, build = run_generator(tmp_path, '<a href="#Value.rec">own</a>')
    uri = f"{SOURCE_REPOSITORY}/blob/{SOURCE_REVISION_PLACEHOLDER}/packages/belay-sqlite/Belay/Sqlite/Schema.lean"
    assert calls[-2][3:] == ["single", "--build", str(build), "Belay.Sqlite.Schema", CORE_DATABASE, uri]
    assert calls[-1][-1] == "Belay.Sqlite.Schema"


def test_model_pages_receive_our_recursor_correction(tmp_path: Path) -> None:
    """Our namespace selection applies the known issue-423 workaround to model pages too."""
    page = tmp_path / "Belay/Sqlite/Schema.html"
    page.parent.mkdir(parents=True)
    page.write_text('<a id="Value"></a><a href="#Value.rec">own</a>')
    assert correct_recursor_links(tmp_path) == 1
    assert 'href="#Value"' in page.read_text()


def test_model_source_links_receive_the_checked_commit(tmp_path: Path) -> None:
    """Our commit-link step processes model pages while preserving their package source paths."""
    base = linked_base(tmp_path, placeholder_link(1))
    page = base / "Belay/Sqlite/Schema.html"
    page.parent.mkdir(parents=True)
    page.write_text(f'<a href="{SOURCE_REPOSITORY}/blob/{SOURCE_REVISION_PLACEHOLDER}/packages/belay-sqlite/Belay/Sqlite/Schema.lean#L1">source</a>')
    assert link_sources(base, tmp_path / "out", REVISION) == 2
    assert f"/blob/{REVISION}/packages/belay-sqlite/" in (tmp_path / "out/Belay/Sqlite/Schema.html").read_text()
