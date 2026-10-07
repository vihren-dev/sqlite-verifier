"""Use the exact doc-gen4 manifest sources as local Lake paths in a Nix build."""

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.source_revision import FULL_COMMIT_HASH_PATTERN

GENERATOR_PACKAGE_NAME: str = "doc-gen4"
"""The generator is the root package; its manifest names only its dependencies."""


@dataclass(frozen=True)
class SourcePin:
    """Keep the original source identity beside its Nix-verified source directory."""

    name: str
    repository: str
    revision: str
    path: Path


def read_pins(pin_file: Path, paths_file: Path) -> dict[str, SourcePin]:
    """Load the fixed source receipt before converting Git dependencies to paths."""
    pins = json.loads(pin_file.read_text())
    paths = json.loads(paths_file.read_text())
    result: dict[str, SourcePin] = {}
    for pin in pins:
        name, repository, revision = (pin[field] for field in ("name", "repository", "revision"))
        if not all(isinstance(value, str) for value in (name, repository, revision)):
            raise ValueError(f"Invalid doc-gen4 pin in {pin_file}; restore the checked source pins")
        if name in result or re.fullmatch(FULL_COMMIT_HASH_PATTERN, revision) is None:
            raise ValueError(f"Invalid doc-gen4 revision for {name}; restore the checked source pins")
        result[name] = SourcePin(name, repository, revision, Path(paths[name]))
    return result


def configure_package(root: Path, destinations: dict[str, Path], pins: dict[str, SourcePin]) -> None:
    """Check each original manifest pin and rewrite its matching fixed require clause."""
    manifest_file = root / "lake-manifest.json"
    manifest = json.loads(manifest_file.read_text())
    for entry in manifest["packages"]:
        pin = pins[entry["name"]]
        url = f"https://github.com/{pin.repository}"
        if entry["type"] != "git" or entry["url"] != url or entry["rev"] != pin.revision:
            raise ValueError(f"Source pin differs from {manifest_file}: {pin.name}; update the pins together")
        relative = os.path.relpath(destinations[pin.name], root)
        config = root / ("lakefile.lean" if (root / "lakefile.lean").is_file() else "lakefile.toml")
        original = config.read_text()
        if config.suffix == ".lean":
            pattern = (rf'require (?:{re.escape(pin.name)}|«{re.escape(pin.name)}») from git\s+'
                       rf'"{re.escape(url)}" @ "{re.escape(entry["inputRev"])}"')
            updated, count = re.subn(pattern, f'require «{pin.name}» from "{relative}"', original)
        else:
            pattern = (rf'\[\[require\]\]\nname = "{re.escape(pin.name)}"\n'
                       rf'scope = "{re.escape(entry["scope"])}"\nrev = "{re.escape(entry["inputRev"])}"')
            updated, count = re.subn(pattern, f'[[require]]\nname = "{pin.name}"\npath = "{relative}"', original)
        if count != 1:
            raise ValueError(f"Expected one pinned require for {pin.name} in {config}; inspect the source update")
        config.write_text(updated)
        for field in ("url", "rev", "inputRev", "subDir"):
            entry.pop(field, None)
        entry.update(type="path", dir=relative)
    manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")


def prepare_dependencies(root: Path, pins: dict[str, SourcePin]) -> None:
    """Copy the five pinned sources and make the complete Lake closure local."""
    manifest = json.loads((root / "lake-manifest.json").read_text())
    names = [entry["name"] for entry in manifest["packages"]]
    if len(names) != len(set(names)) or set(names) != set(pins) - {GENERATOR_PACKAGE_NAME}:
        raise ValueError(f"Dependency set differs in {root}; update the pinned closure together")
    destinations = {name: root / ".lake/packages" / name for name in names}
    for name, destination in destinations.items():
        shutil.copytree(pins[name].path, destination)
        for path in destination.rglob("*"):
            path.chmod(path.stat().st_mode | 0o200)
        destination.chmod(destination.stat().st_mode | 0o200)
    configure_package(root, destinations, pins)
    for destination in destinations.values():
        configure_package(destination, destinations, pins)


def main() -> None:
    """Accept only the Nix source receipt and the unpacked doc-gen4 package."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("pins", type=Path)
    parser.add_argument("paths", type=Path)
    arguments = parser.parse_args()
    prepare_dependencies(arguments.root.resolve(), read_pins(arguments.pins, arguments.paths))


if __name__ == "__main__":
    main()
