"""Real Nix must snapshot only tiny pins in both Git-parent and non-Git workspaces."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_resources import check_environment, MAX_ENVIRONMENT_BYTES


def run(arguments: list[str], directory: Path) -> str:
    """Only bounded local metadata operations run; no package builds or input updates."""
    return subprocess.run(arguments, cwd=directory, check=True, capture_output=True,
                          text=True, timeout=30).stdout


def identity(directory: Path) -> tuple[str, str, int]:
    """Measure the actual copied store source, not a derivation's later src filter."""
    check_environment(directory)
    metadata = json.loads(run(['nix', 'flake', 'metadata', '--offline', '--json',
                               '--no-write-lock-file', 'path:./nix'], directory))
    assert metadata['resolvedUrl'].startswith('path:'), metadata
    source = Path(metadata['path'])
    assert {entry.name for entry in source.iterdir()} == {'flake.nix', 'flake.lock'}
    information = json.loads(run(['nix', 'path-info', '--json', str(source)], directory))
    info = information[0] if isinstance(information, list) else information[str(source)]
    assert info['narSize'] < MAX_ENVIRONMENT_BYTES, info
    return str(source), info['narHash'], info['narSize']


def main() -> None:
    """Outside source/artifact/metadata edits cannot affect the environment source identity."""
    check_environment(ROOT)
    with TemporaryDirectory(prefix='environment-boundary-') as temporary:
        for git_parent in (False, True):
            directory = Path(temporary) / ('git-parent' if git_parent else 'non-git')
            shutil.copytree(ROOT / 'nix', directory / 'nix')
            (directory / 'source.txt').write_text('before\n')
            if git_parent:
                run(['git', 'init', '--quiet'], directory)
                run(['git', 'add', 'nix', 'source.txt'], directory)
            before = identity(directory)
            for name in ('dist', 'build', '.lake', '.jj'):
                folder = directory / name
                folder.mkdir()
                with (folder / 'generated').open('wb') as output:
                    output.truncate(2 * 1024 * 1024)
            (directory / 'source.txt').write_text('after\n')
            after = identity(directory)
            assert before == after, (git_parent, before, after)
            print(f'Environment snapshot: git_parent={git_parent}, size={after[2]}, unchanged={after[0]}')


if __name__ == '__main__':
    main()
