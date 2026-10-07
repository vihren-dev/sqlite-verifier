"""Resolve split Lean package directories without changing ordered artifact precedence."""

from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory


@contextmanager
def merged_search_path(roots: Sequence[Path], workspace: Path) -> Iterator[tuple[Path, ...]]:
    """Expose all sibling modules while selecting the first existing file from the original roots.

    Lean selects a package directory before looking for its individual modules.
    A candidate sibling therefore needs a merged package view when the trusted
    library already supplies that package. Original artifacts stay in place.
    Package names follow the case rules of the merged directory's filesystem.
    """
    with TemporaryDirectory(prefix="import-path-", dir=workspace) as temporary:
        merged = Path(temporary)
        case_sensitive = not merged.with_name(merged.name.swapcase()).exists()
        packages: dict[str, list[Path]] = {}
        for root in roots:
            for entry in root.iterdir():
                if entry.is_dir():
                    key = entry.name if case_sensitive else entry.name.casefold()
                    packages.setdefault(key, []).append(entry)
        split = {key: directories for key, directories in packages.items() if len(directories) > 1}
        if not split:
            yield tuple(roots)
            return
        for key, directories in split.items():
            name = directories[0].name
            for directory in directories:
                for source in directory.rglob("*"):
                    if source.is_file():
                        target = merged / name / source.relative_to(directory)
                        if not target.exists():
                            target.parent.mkdir(parents=True, exist_ok=True)
                            target.symlink_to(source.resolve())
            for root in roots:
                for source in root.iterdir():
                    package = source.name.split(".", 1)[0]
                    if source.is_file() and (package if case_sensitive else package.casefold()) == key:
                        target = merged / source.name
                        if not target.exists():
                            target.symlink_to(source.resolve())
        yield (merged, *roots)
