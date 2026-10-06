"""Exercise optional archive setup through the actual catalog pytest entry point."""

import os
from pathlib import Path
import sys

import pytest

from conformance.upstream_catalog import catalog_patterns
from tests.runtime_support import run_command

pytestmark = [pytest.mark.integration, pytest.mark.conformance]
ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize('archive_state', ['absent', 'empty', 'invalid', 'missing', 'extra', 'valid'])
def test_catalog_archive_environment(archive_state: str, tmp_path: Path) -> None:
    """Only an unset archive skips; configured paths execute or fail the catalog checks."""
    environment = dict(os.environ)
    environment.pop('CONFORMANCE_UPSTREAM', None)
    environment['PYTEST_DISABLE_PLUGIN_AUTOLOAD'] = '1'
    archive = tmp_path / 'upstream'
    if archive_state != 'absent':
        environment['CONFORMANCE_UPSTREAM'] = '' if archive_state == 'empty' else str(archive)
    if archive_state in ('missing', 'extra', 'valid'):
        (archive / 'test').mkdir(parents=True)
        for filename in catalog_patterns():
            (archive / 'test' / filename).touch()
        if archive_state == 'missing':
            (archive / 'test/fkey8.test').unlink()
        elif archive_state == 'extra':
            (archive / 'test/selectZ.test').touch()
    result = run_command([sys.executable, '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
                          'tests/conformance_catalog_test.py'],
                         cwd=ROOT, timeout=10, environment=environment)
    assert 'KeyError' not in result.stdout, result.diagnostic()
    if archive_state == 'absent':
        assert result.returncode == 0 and '3 skipped' in result.stdout, result.diagnostic()
        assert 'CONFORMANCE_UPSTREAM is unset' in result.stdout, result.diagnostic()
        assert 'nix-build build-support/default.nix -A tests.upstream' in result.stdout, result.diagnostic()
    else:
        assert 'skipped' not in result.stdout, result.diagnostic()
        if archive_state == 'valid':
            assert result.returncode == 0 and '3 passed' in result.stdout, result.diagnostic()
        else:
            assert result.returncode == 1, result.diagnostic()
            diagnostic = ('CONFORMANCE_UPSTREAM has no test directory' if archive_state in ('empty', 'invalid')
                          else 'pinned feature families')
            assert diagnostic in result.stdout, result.diagnostic()
