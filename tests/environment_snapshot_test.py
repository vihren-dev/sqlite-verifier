"""Real Nix must snapshot only tiny pins in both Git-parent and non-Git workspaces."""

import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.environment, pytest.mark.requires_nix]

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
    assert {entry.name for entry in source.iterdir()} == {'flake.nix', 'flake.lock', 'sqlite.nix'}
    information = json.loads(run(['nix', 'path-info', '--json', str(source)], directory))
    info = information[0] if isinstance(information, list) else information[str(source)]
    assert info['narSize'] < MAX_ENVIRONMENT_BYTES, info
    return str(source), info['narHash'], info['narSize']


@pytest.mark.parametrize("git_parent", [pytest.param(False, id="non_git"),
    pytest.param(True, id="git_parent", marks=pytest.mark.requires_native("git"))])
def test_environment_snapshot(git_parent: bool, tmp_path: Path) -> None:
    """Outside source/artifact/metadata edits cannot change the tiny explicit path-flake snapshot."""
    check_environment(ROOT)
    directory = tmp_path / ('git-parent' if git_parent else 'non-git')
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
    assert before == identity(directory)
