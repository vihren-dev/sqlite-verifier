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
    Package names follow the original roots' case rules. The merged view exposes
    each original spelling when its filesystem distinguishes letter case.
    """
    with TemporaryDirectory(prefix="import-path-", dir=workspace) as temporary:
        merged = Path(temporary)
        directories = [entry for root in roots for entry in root.iterdir() if entry.is_dir()]
        case_aliases = {entry.name.casefold() for entry in directories
                        if entry.with_name(entry.name.swapcase()).exists()
                        and entry.with_name(entry.name.swapcase()).samefile(entry)}
        packages: dict[str, list[Path]] = {}
        for entry in directories:
            key = entry.name.casefold() if entry.name.casefold() in case_aliases else entry.name
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
                            relative = source.relative_to(directory)
                            selected = next((base / relative for base in directories
                                             if (base / relative).is_file()), source)
                            target.symlink_to(selected.resolve())
            for root in roots:
                for source in root.iterdir():
                    package = source.name.split(".", 1)[0]
                    folded = package.casefold() in case_aliases
                    if source.is_file() and (package.casefold() if folded else package) == key:
                        target = merged / source.name
                        if not target.exists():
                            selected = next((base / source.name for base in roots
                                             if (base / source.name).is_file()), source)
                            target.symlink_to(selected.resolve())
            for directory in directories:
                alias = merged / directory.name
                if not alias.exists():
                    alias.symlink_to(name, target_is_directory=True)
        yield (merged, *roots)
