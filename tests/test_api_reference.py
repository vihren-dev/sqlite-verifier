"""A generated reference must contain its public modules and resolve its local links."""

import json
from pathlib import Path
import re

import pytest

from tools.api_reference import (SOURCE_REPOSITORY, SOURCE_REVISION_PLACEHOLDER, correct_reference_links,
                                  validate_reference)
from tools.api_reference_links import link_sources
from tools.ci_store_gc import TARGETS
from tools.source_revision import FULL_COMMIT_HASH_PATTERN

pytestmark = [pytest.mark.unit, pytest.mark.environment]
REVISION = "1234567890abcdef1234567890abcdef12345678"
"""A complete source identity used by the isolated reference fixture."""


def test_nix_and_python_source_revision_policy_agree() -> None:
    """Both build-boundary checks enforce the same full-commit requirement."""
    definition = Path(__file__).resolve().parents[1] / "build-support/api-reference-links.nix"
    match = re.search(r'fullCommitHashPattern = "([^"]+)";', definition.read_text())
    assert match is not None
    assert match.group(1) == FULL_COMMIT_HASH_PATTERN


def reference_fixture(root: Path) -> tuple[Path, Path]:
    """Create one linked declaration and a module walkthrough without invoking Lean."""
    source = root / "source"
    (source / "SqliteVerifier").mkdir(parents=True)
    (source / "SqliteVerifier.lean").write_text("import SqliteVerifier.Model\n")
    (source / "SqliteVerifier/Model.lean").write_text("def example := 1\n")
    output = root / "reference"
    (output / "SqliteVerifier").mkdir(parents=True)
    (root / "doc-data").mkdir()
    (output / "SqliteVerifier.html").write_text('<p>Walkthrough</p><a href="SqliteVerifier/Model.html#example">Model</a>')
    (output / "SqliteVerifier/Model.html").write_text('<a id="example"></a><a href="../SqliteVerifier.html">Library</a>')
    for module in ("SqliteVerifier", "SqliteVerifier.Model"):
        declarations = [] if module == "SqliteVerifier" else [{"info": {"sourceLink":
            f"{SOURCE_REPOSITORY}/blob/{REVISION}/SqliteVerifier/Model.lean#L1-L1"}}]
        (root / f"doc-data/declaration-data-{module}.bmp").write_text(json.dumps({"declarations": declarations}))
    return output, source


def test_reference_accepts_complete_linked_modules(tmp_path: Path) -> None:
    """The artifact receipt counts actual public declarations and resolved local links."""
    output, source = reference_fixture(tmp_path)
    assert validate_reference(output, source, REVISION) == {
        "public_modules": 2, "public_declarations": 1, "html_pages": 2, "local_links": 2}


@pytest.mark.parametrize("link", ["#top", "#TOP", "#named", "#raw%20name", "#decoded%20name"])
def test_standard_html_fragment_targets(tmp_path: Path, link: str) -> None:
    """HTML accepts named anchors, raw or decoded IDs, and its special document-start fragment."""
    output, source = reference_fixture(tmp_path)
    (output / "SqliteVerifier.html").write_text(
        f'<a name="named"></a><p id="raw%20name"></p><p id="decoded name"></p><a href="{link}">target</a>')
    assert validate_reference(output, source, REVISION)["local_links"] == 2


def test_known_generator_links_are_corrected_to_existing_targets(tmp_path: Path) -> None:
    """Only missing generated recursors and the pinned core typo receive real existing targets."""
    output, source = reference_fixture(tmp_path)
    (output / "Init").mkdir()
    (output / "Init/Tactics.html").write_text("<p>Tactics</p>")
    (output / "SqliteVerifier.html").write_text(
        '<a href="SqliteVerifier/Model.html#example.rec">recursor</a>'
        '<a href="Init/Tactic.html">tactics</a>')
    assert correct_reference_links(output) == 2
    assert 'href="SqliteVerifier/Model.html#example"' in (output / "SqliteVerifier.html").read_text()
    assert validate_reference(output, source, REVISION)["local_links"] == 3
    assert correct_reference_links(output) == 0


def test_existing_raw_fragment_is_preserved(tmp_path: Path) -> None:
    """HTML gives an existing raw ID precedence over percent decoding and parent-type correction."""
    output, source = reference_fixture(tmp_path)
    text = '<a id="example%20.rec"></a><a id="example "></a><a href="#example%20.rec">raw ID</a>'
    (output / "SqliteVerifier.html").write_text(text)
    assert correct_reference_links(output) == 0
    assert (output / "SqliteVerifier.html").read_text() == text
    assert validate_reference(output, source, REVISION)["local_links"] == 2


@pytest.mark.parametrize("damage", ["module", "file", "anchor", "escape", "revision", "source"])
def test_reference_rejects_incomplete_or_misidentified_output(tmp_path: Path, damage: str) -> None:
    """Missing pages, links, anchors and source identities cannot produce a checked artifact."""
    output, source = reference_fixture(tmp_path)
    revision = REVISION
    if damage == "module":
        (output / "SqliteVerifier/Model.html").unlink()
    elif damage == "file":
        (output / "SqliteVerifier.html").write_text('<a href="missing.html">missing</a>')
    elif damage == "anchor":
        (output / "SqliteVerifier.html").write_text('<a href="SqliteVerifier/Model.html#missing">missing</a>')
    elif damage == "escape":
        (output / "SqliteVerifier.html").write_text('<a href="../source/SqliteVerifier.lean">outside</a>')
    elif damage == "revision":
        revision = "main"
    else:
        data = output.parent / "doc-data/declaration-data-SqliteVerifier.Model.bmp"
        data.write_text(data.read_text().replace(REVISION, "0" * 40))
    with pytest.raises(ValueError):
        validate_reference(output, source, revision)


def test_base_build_has_no_commit_and_survives_cache_cleanup() -> None:
    """Only the cheap link step takes the commit, and CI keeps the reusable base build."""
    build_support = Path(__file__).resolve().parents[1] / "build-support"
    base = (build_support / "api-reference.nix").read_text()
    assert "{ pkgs, sources, leanToolchain, lean4export, docGen4, inventoryTools }:" in base
    assert "--revision" not in base and "referenceRevision" not in base
    assert "base = apiReferenceBase;" in (build_support / "default.nix").read_text()
    assert "apiReferenceBase" in TARGETS


def test_base_build_validates_placeholder_links(tmp_path: Path) -> None:
    """The base build checks its source links against the placeholder, not a commit."""
    output, source = reference_fixture(tmp_path)
    data = tmp_path / "doc-data/declaration-data-SqliteVerifier.Model.bmp"
    data.write_text(data.read_text().replace(REVISION, SOURCE_REVISION_PLACEHOLDER))
    assert validate_reference(output, source, SOURCE_REVISION_PLACEHOLDER)["public_declarations"] == 1
    with pytest.raises(ValueError):
        validate_reference(output, source, REVISION)


def linked_base(root: Path, page: str) -> Path:
    """A base reference with one page and the check report of the base build."""
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
