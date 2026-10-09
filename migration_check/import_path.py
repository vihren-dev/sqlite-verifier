"""Expose caller siblings while preserving each requested spelling's original file origins."""

from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory

ARTIFACT_SUFFIXES = (".olean", ".olean.server", ".olean.private", ".ir", ".ir.sig")
"""Lean reads these companion files beside a module's compiled object."""


def ignores_package_case(directory: Path) -> bool:
    """Probe an existing directory alias on its own volume, independently of the other roots."""
    alias = directory.with_name(directory.name.swapcase())
    return alias.exists() and alias.samefile(directory)


def package_directory(root: Path, spelling: str) -> Path | None:
    """Use the original filesystem lookup to determine whether this root supplies a spelling."""
    path = root / spelling
    return path if path.is_dir() else None


def package_view(roots: Sequence[Path], spelling: str,
                 requested: Sequence[Path]) -> dict[Path, Path]:
    """Choose the first original file for every sibling and explicitly requested module spelling."""
    directories = [path for root in roots if (path := package_directory(root, spelling)) is not None]
    relative_files = {path.relative_to(directory) for directory in directories
                      for path in directory.rglob("*") if path.is_file()}
    for module in requested:
        if len(module.parts) > 1 and module.parts[0] == spelling:
            relative = Path(*module.parts[1:])
            relative_files.update(relative.with_suffix(relative.suffix + suffix)
                                  for suffix in ARTIFACT_SUFFIXES)
    view: dict[Path, Path] = {}
    for relative in sorted(relative_files):
        selected = next((directory / relative for directory in directories
                         if (directory / relative).is_file()), None)
        if selected is not None:
            view[Path(spelling) / relative] = selected
    for suffix in ARTIFACT_SUFFIXES:
        relative = Path(spelling + suffix)
        selected = next((root / relative for root in roots if (root / relative).is_file()), None)
        if selected is not None:
            view[relative] = selected
    return view


def compatible_links(links: dict[Path, Path], *, ignores_case: bool) -> dict[Path, Path]:
    """Refuse only origins that the chosen workspace cannot represent as distinct files."""
    retained: dict[Path, Path] = {}
    identities: dict[str, Path] = {}
    for relative, source in links.items():
        key = relative.as_posix().casefold() if ignores_case else relative.as_posix()
        previous = identities.get(key)
        if previous is not None and not source.samefile(previous):
            raise ValueError(f"Workspace cannot distinguish module paths with different origins: {relative}; "
                             "choose a case-sensitive workspace")
        if previous is None:
            retained[relative] = source
            identities[key] = source
    return retained


def compatible_views(views: dict[str, dict[Path, Path]], *, ignores_case: bool) -> None:
    """Preserve missing siblings as well as selected origins when the workspace folds spellings."""
    if not ignores_case:
        return
    families: dict[str, dict[str, Path]] = {}
    for name, links in views.items():
        entries = {(path.relative_to(name).as_posix() if path.parts[0] == name
                    else path.name[len(name):]).casefold(): source for path, source in links.items()}
        previous = families.get(name.casefold())
        if previous is not None and (entries.keys() != previous.keys()
                or any(not source.samefile(previous[key]) for key, source in entries.items())):
            raise ValueError(f"Workspace cannot preserve distinct package views for {name}; "
                             "choose a case-sensitive workspace")
        families[name.casefold()] = entries


@contextmanager
def merged_search_path(roots: Sequence[Path], workspace: Path, *,
                       requested: Sequence[Path] = ()) -> Iterator[tuple[Path, ...]]:
    """Expose split packages using original lookups for every requested spelling.

    Matching spellings retain caller siblings. Differently cased spellings get
    separate views determined by the original roots. A case-insensitive workspace
    can combine identical origins; distinct origins require a case-sensitive
    workspace. Callers supply module paths parsed by Lean to retain their spelling.
    """
    for path in requested:
        if not path.parts or path.is_absolute() or any(part in {".", ".."} for part in path.parts):
            raise ValueError(f"Invalid module path {str(path)!r}; give a relative Lean module path "
                             "with no '.' or '..' parts")
    names = {entry.name for root in roots for entry in root.iterdir() if entry.is_dir()}
    names.update(path.parts[0] for path in requested if path.parts)
    # Other casings can differ even when both directories use the same spelling.
    names.update(name.swapcase() for name in tuple(names))
    participants = {name: sum(package_directory(root, name) is not None for root in roots)
                    for name in names}
    families = {name.casefold() for name, count in participants.items() if count > 1}
    if not families:
        yield tuple(roots)
        return
    views: dict[str, dict[Path, Path]] = {}
    for name in sorted(names):
        if name.casefold() in families:
            views[name] = package_view(roots, name, requested)
    with TemporaryDirectory(prefix="import-path-", dir=workspace) as temporary:
        merged = Path(temporary)
        ignores_case = ignores_package_case(merged)
        compatible_views(views, ignores_case=ignores_case)
        links = {path: source for view in views.values() for path, source in view.items()}
        selected = compatible_links(links, ignores_case=ignores_case)
        for relative, source in selected.items():
            target = merged / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(source.resolve())
        yield (merged, *roots)
