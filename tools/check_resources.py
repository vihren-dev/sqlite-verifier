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
    """Only the two regular pinned files belong in the environment source boundary."""
    directory = root / 'nix'
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError(f'Environment must be a real directory: {directory}')
    expected = {'flake.nix', 'flake.lock'}
    size = 0
    found: set[str] = set()
    for path in directory.iterdir():
        if path.name not in expected or path.is_symlink() or not path.is_file():
            raise ValueError(f'Unexpected environment input: {path}; only regular flake.nix/flake.lock are allowed')
        found.add(path.name)
        size += path.stat().st_size
        if size > MAX_ENVIRONMENT_BYTES:
            raise ValueError('Environment inputs exceed 1 MiB; keep generated artifacts outside nix/')
    if found != expected:
        raise ValueError(f'Environment requires both flake.nix and flake.lock in {directory}')
    return size


def existing_parent(path: Path) -> Path:
    """Locate the actual destination filesystem even before an output directory exists."""
    path = path.resolve()
    while not path.exists():
        path = path.parent
    return path


def check_resources(root: Path = ROOT) -> None:
    """Check workspace, temporary, toolchain and Nix-store write destinations separately."""
    check_environment(root)
    destinations = [root / 'dist', root / 'build', root / '.lake', Path(tempfile.gettempdir()),
                    Path(os.environ.get('ELAN_HOME', str(Path.home() / '.elan')))]
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
