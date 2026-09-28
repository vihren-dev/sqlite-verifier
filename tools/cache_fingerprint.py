"""Fingerprint declared build/test inputs independently of Git or Jujutsu metadata."""

import argparse
from collections.abc import Iterable
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENVIRONMENT_FILES = ("nix/flake.nix", "nix/flake.lock", "lean-toolchain")
SOURCE_FILES = ("LICENSE", "lakefile.toml", "lake-manifest.json", "pytest.ini", "justfile",
                ".envrc", "docs/install.md")
# A conservative superset of build-support/sources.nix plus all test/coverage inputs.
SOURCE_TREES: dict[str, tuple[str, ...]] = {
    "SqliteVerifier": (".lean",), "parser": (".py", ".c", ".h", ".y", ".json"),
    "migration_check": (".py",), "packaging": (".py", ".sh"), "tools": (".py",),
    "build-support": (), "bin": (), "examples": (), "tests": (), "conformance": (),
}
GENERATED_DIRECTORIES = {".git", ".jj", ".lake", "build", "dist", "__pycache__"}


def source_files(root: Path) -> list[Path]:
    """Collect complete membership while pruning the same generated trees as Nix."""
    paths = [root / name for name in SOURCE_FILES]
    paths.extend(root.glob("*.lean"))
    for directory, extensions in SOURCE_TREES.items():
        base = root / directory
        if base.is_symlink():
            raise ValueError(f"Cache input directory is a symlink: {base}")
        if not base.is_dir():
            raise FileNotFoundError(base)
        for current, directories, files in os.walk(base, followlinks=False):
            directories[:] = sorted(name for name in directories if name not in GENERATED_DIRECTORIES)
            for name in directories:
                if (Path(current) / name).is_symlink():
                    raise ValueError(f"Cache input directory is a symlink: {Path(current) / name}")
            for name in files:
                path = Path(current) / name
                if name == ".DS_Store" or path.suffix == ".pyc":
                    continue
                if directory == "build-support" and path.suffix == ".md":
                    continue
                if not extensions or path.suffix in extensions:
                    paths.append(path)
    return paths


def fingerprint(root: Path, paths: Iterable[Path]) -> str:
    """Hash an unambiguous sorted path/content/executable manifest, including membership."""
    manifest: list[tuple[str, str, bool]] = []
    for path in sorted(set(paths)):
        if any(parent.is_symlink() for parent in (path, *path.parents)
               if parent.is_relative_to(root)) or not path.is_file():
            raise ValueError(f"Cache input must be a regular file: {path}")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        manifest.append((path.relative_to(root).as_posix(), digest, bool(path.stat().st_mode & 0o111)))
    return hashlib.sha256(json.dumps(manifest, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()


def cache_keys(root: Path, system: str) -> dict[str, str]:
    """Separate pin compatibility from exact source identity for safe store restoration."""
    if system not in {"aarch64-darwin", "x86_64-linux"}:
        raise ValueError(f"Unsupported native system: {system}")
    root = root.resolve(strict=True)
    environment = fingerprint(root, (root / name for name in ENVIRONMENT_FILES))
    source = fingerprint(root, source_files(root))
    prefix = f"build-v2-{system}-{environment}-"
    return {"env_hash": environment, "source_hash": source, "prefix": prefix, "key": prefix + source}


def main() -> None:
    """Emit reviewable JSON and optionally GitHub step outputs without shell interpolation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--system", choices=("aarch64-darwin", "x86_64-linux"), required=True)
    parser.add_argument("--github-output", type=Path)
    arguments = parser.parse_args()
    keys = cache_keys(arguments.root, arguments.system)
    if arguments.github_output is not None:
        with arguments.github_output.open("a") as output:
            output.writelines(f"{name}={value}\n" for name, value in keys.items())
    print(json.dumps(keys, sort_keys=True))


if __name__ == "__main__":
    main()
