"""Fail before expensive writes or oversized Nix environment snapshots."""

import argparse
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MIN_FREE_BYTES = 10 * 1024 ** 3
MAX_ENVIRONMENT_BYTES = 1024 ** 2


def check_environment(root: Path) -> int:
    """Only the declared regular environment files belong in the environment source boundary."""
    directory = root / 'nix'
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError(f'Environment must be a real directory: {directory}')
    expected = {'flake.nix', 'flake.lock', 'sqlite.nix'}
    size = 0
    found: set[str] = set()
    for path in directory.iterdir():
        if path.name not in expected or path.is_symlink() or not path.is_file():
            raise ValueError(f'Unexpected environment input: {path}; only regular flake.nix/flake.lock/sqlite.nix are allowed')
        found.add(path.name)
        size += path.stat().st_size
        if size > MAX_ENVIRONMENT_BYTES:
            raise ValueError('Environment inputs exceed 1 MiB; keep generated artifacts outside nix/')
    if found != expected:
        raise ValueError(f'Environment requires flake.nix, flake.lock and sqlite.nix in {directory}')
    return size


def existing_parent(path: Path) -> Path:
    """Locate the actual destination filesystem even before an output directory exists."""
    path = path.resolve()
    while not path.exists():
        path = path.parent
    return path


def check_resources(root: Path = ROOT, *, temporary_root: Path | None = None) -> None:
    """Check workspace, temporary, toolchain and Nix-store write destinations separately."""
    check_environment(root)
    temporary = temporary_root.resolve() if temporary_root is not None else Path(tempfile.gettempdir())
    if temporary_root is not None and not temporary.is_dir():
        raise ValueError(f'Temporary storage directory is missing or invalid: {temporary}; '
                         'select an existing writable directory')
    destinations = [root / 'dist', root / 'build', root / '.lake', temporary]
    if Path('/nix/store').exists():
        destinations.append(Path('/nix/store'))
    failures: list[str] = []
    seen: set[int] = set()
    for destination in destinations:
        actual = existing_parent(destination)
        device = actual.stat().st_dev
        if device in seen:
            continue
        seen.add(device)
        available = shutil.disk_usage(actual).free
        if available < MIN_FREE_BYTES:
            failures.append(f'{actual}: {available / 1024 ** 3:.2f} GiB free')
    if failures:
        raise ValueError('At least 10 GiB free is required before expensive development work: ' +
                         '; '.join(failures) + '. Stop and request targeted cleanup approval; no automatic deletion.')
    if temporary_root is not None:
        try:
            with tempfile.TemporaryDirectory(prefix='native-storage-check-', dir=temporary):
                pass
        except OSError as error:
            raise ValueError(f'Temporary storage directory is not writable: {temporary}; '
                             'select a writable directory with sufficient free space') from error


def main() -> None:
    """Allow lightweight source-boundary checks without authorizing expensive work."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment-only', action='store_true')
    args = parser.parse_args()
    try:
        if args.environment_only:
            check_environment(ROOT)
        else:
            check_resources(ROOT)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error


if __name__ == '__main__':
    main()
