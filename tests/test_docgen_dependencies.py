"""Pinned manifest conversion retains exact sources while removing sandbox Git dependencies."""

import json
from pathlib import Path

import pytest

from tools.docgen_dependencies import SourcePin, prepare_dependencies, read_pins

pytestmark = [pytest.mark.unit, pytest.mark.environment]
REVISION = "1234567890abcdef1234567890abcdef12345678"
"""The fixed dependency revision used to reject a changed upstream manifest."""


def dependency_fixture(root: Path) -> tuple[Path, dict[str, SourcePin]]:
    """Make one direct native-style Lean dependency and its scoped TOML dependency."""
    packages = {name: root / name for name in ("doc-gen4", "BibtexQuery", "UnicodeBasic")}
    pins = {name: SourcePin(name, f"owner/{name}", REVISION, path) for name, path in packages.items()}
    for name, path in packages.items():
        path.mkdir()
        dependency = "BibtexQuery" if name == "doc-gen4" else "UnicodeBasic"
        entries = [] if name == "UnicodeBasic" else [{"name": dependency, "type": "git",
            "url": f"https://github.com/owner/{dependency}", "rev": REVISION,
            "inputRev": "main", "scope": "owner"}]
        if name == "doc-gen4":
            entries.append({"name": "UnicodeBasic", "type": "git",
                "url": "https://github.com/owner/UnicodeBasic", "rev": REVISION,
                "inputRev": "main", "scope": ""})
            (path / "lakefile.lean").write_text('require BibtexQuery from git\n  "https://github.com/owner/BibtexQuery" @ "main"\n'
                'require «UnicodeBasic» from git\n  "https://github.com/owner/UnicodeBasic" @ "main"\n')
        else:
            requires = '' if name == "UnicodeBasic" else '[[require]]\nname = "UnicodeBasic"\nscope = "owner"\nrev = "main"\n'
            (path / "lakefile.toml").write_text(f'name = "{name}"\n{requires}')
        (path / "lake-manifest.json").write_text(json.dumps({"packages": entries}))
    return packages["doc-gen4"], pins


def test_pinned_closure_uses_only_existing_local_paths(tmp_path: Path) -> None:
    """Direct and transitive requires resolve to copied source directories without Git entries."""
    package, pins = dependency_fixture(tmp_path)
    prepare_dependencies(package, pins)
    for manifest_file in package.rglob("lake-manifest.json"):
        for entry in json.loads(manifest_file.read_text())["packages"]:
            assert entry["type"] == "path"
            assert (manifest_file.parent / entry["dir"]).is_dir()
    assert "from git" not in (package / "lakefile.lean").read_text()
    assert 'path = "../UnicodeBasic"' in (package / ".lake/packages/BibtexQuery/lakefile.toml").read_text()


def test_changed_upstream_revision_is_rejected(tmp_path: Path) -> None:
    """An exact source pin must agree with the fetched generator's own manifest."""
    package, pins = dependency_fixture(tmp_path)
    manifest = package / "lake-manifest.json"
    manifest.write_text(manifest.read_text().replace(REVISION, "0" * 40))
    with pytest.raises(ValueError, match="Source pin differs"):
        prepare_dependencies(package, pins)


@pytest.mark.parametrize("damage", ["duplicate", "revision"])
def test_source_pin_identity_is_complete_and_unique(tmp_path: Path, damage: str) -> None:
    """A duplicate source name or branch-shaped revision cannot replace an exact source pin."""
    _, pins = dependency_fixture(tmp_path)
    rows = [{"name": pin.name, "repository": pin.repository, "revision": pin.revision} for pin in pins.values()]
    if damage == "duplicate":
        rows.append(rows[0])
    else:
        rows[0]["revision"] = "main"
    pin_file, paths_file = tmp_path / "pins.json", tmp_path / "paths.json"
    pin_file.write_text(json.dumps(rows))
    paths_file.write_text(json.dumps({name: str(pin.path) for name, pin in pins.items()}))
    with pytest.raises(ValueError, match="Invalid doc-gen4 revision"):
        read_pins(pin_file, paths_file)


@pytest.mark.parametrize("damage", ["extra", "missing"])
def test_original_manifest_dependency_set_is_exact(tmp_path: Path, damage: str) -> None:
    """A source closure cannot silently gain or lose a dependency from its pinned receipt."""
    package, pins = dependency_fixture(tmp_path)
    manifest_file = package / "lake-manifest.json"
    manifest = json.loads(manifest_file.read_text())
    if damage == "extra":
        manifest["packages"].append({"name": "Unexpected"})
    else:
        manifest["packages"].pop()
    manifest_file.write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="Dependency set differs"):
        prepare_dependencies(package, pins)
