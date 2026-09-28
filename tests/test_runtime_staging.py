"""Archive export delegates dependency closure and integrity to Nix."""

import json
from pathlib import Path
import sys
import tarfile
from types import SimpleNamespace
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'packaging'))
import build_runtime

pytestmark = [pytest.mark.unit, pytest.mark.packaging]


def write(root: Path, name: str, content: str = 'fixture') -> Path:
    """Create tiny immutable-runtime fixtures without native builds."""
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path


@pytest.mark.parametrize('system,architecture,target', [
    ('Darwin', 'arm64', 'aarch64-darwin'), ('Linux', 'x86_64', 'x86_64-linux'),
])
def test_archive_exports_content_addressed_closure(tmp_path: Path, system: str,
                                                  architecture: str, target: str) -> None:
    """Export only the rewritten runtime closure with verification enabled and no copied payload."""
    root, addressed = tmp_path / 'runtime', tmp_path / 'addressed'
    for name in ('packaging/install.py', 'packaging/install.sh', 'docs/install.md'):
        write(addressed, name)
    write(root, 'platform', target + '\n')
    write(addressed, 'platform', target + '\n')
    write(addressed, 'python-path', '/nix/store/addressed-python/bin/python3\n')
    commands = []

    def run(command: list[str], timeout: int = 300) -> str:
        """Return Nix's rewrite mapping and record the exact closure export and integrity policy."""
        commands.append(command)
        if 'make-content-addressed' in command:
            return json.dumps({'rewrites': {str(root): str(addressed)}})
        return ''

    with patch.object(build_runtime, 'check_resources'), \
         patch.object(build_runtime.shutil, 'disk_usage', return_value=SimpleNamespace(free=20 * 1024**3)), \
         patch.object(build_runtime.platform, 'system', return_value=system), \
         patch.object(build_runtime.platform, 'machine', return_value=architecture), \
         patch.object(build_runtime, 'store_runtime', side_effect=lambda path: path), \
         patch.object(build_runtime, 'run', side_effect=run):
        archive = build_runtime.build(root, output_dir=tmp_path / 'output ü space')
    with tarfile.open(archive) as bundle:
        prefix = f'sqlite-verifier-{target}/'
        assert not any('/payload' in name for name in bundle.getnames())
        assert bundle.extractfile(prefix + 'runtime-path').read().decode() == str(addressed) + '\n'
        assert bundle.extractfile(prefix + 'nix-paths').read().decode() == str(addressed) + '\n'
        assert bundle.extractfile(prefix + 'python-path').read().decode() == '/nix/store/addressed-python/bin/python3\n'
    assert archive.with_suffix('.gz.sha256').is_file()
    assert any('copy' in command and command[-1] == str(addressed) for command in commands)
    assert any('--sigs-needed' in command and command[-1] == '1' for command in commands)
    assert all('--offline' in command for command in commands if command[0] == 'nix')
    assert not any('--no-check-sigs' in command or 'require-sigs' in command for command in commands)


def test_explicit_runtime_never_falls_back_to_ambient_lean(tmp_path: Path) -> None:
    """A checkout is not a runtime; packaging never probes an ambient compiler."""
    with patch.object(build_runtime, 'check_resources'), \
         patch.object(build_runtime.shutil, 'disk_usage', return_value=SimpleNamespace(free=20 * 1024**3)), \
         patch.object(build_runtime, 'run') as run:
        with pytest.raises(ValueError, match='Expected a Nix runtime'):
            build_runtime.build(tmp_path, output_dir=tmp_path / 'output')
        run.assert_not_called()


@pytest.mark.parametrize('destination,free,message', [
    ('output', 0, '10 GiB'),
    ('/nix/store/forbidden-archive', 20 * 1024**3, 'immutable Nix store'),
])
def test_archive_output_preflight_precedes_tool_reads(
    tmp_path: Path, destination: str, free: int, message: str,
) -> None:
    """A separate full filesystem or immutable output stops before inspecting tools."""
    output = tmp_path / destination
    with patch.object(build_runtime, 'check_resources'), \
         patch.object(build_runtime.shutil, 'disk_usage', return_value=SimpleNamespace(free=free)), \
         patch.object(build_runtime, 'run') as run:
        with pytest.raises(ValueError, match=message):
            build_runtime.build(tmp_path, output_dir=output)
        run.assert_not_called()
    assert not output.exists()
