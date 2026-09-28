"""Check bounded execution independently of any OS isolation mechanism."""

from pathlib import Path
import subprocess
import sys

import pytest

from migration_check.process import run_process

pytestmark = [pytest.mark.integration, pytest.mark.environment]


def test_output_limit(tmp_path: Path) -> None:
    """A noisy child cannot grow its output file or returned diagnostics without bound."""
    result = run_process([sys.executable, '-I', '-c', "import sys; sys.stdout.write('x' * 20_000_000)"],
                         write_root=tmp_path, environment={}, timeout=5)
    assert result.returncode != 0
    assert len(result.stdout) == 1024 * 1024


def test_timeout(tmp_path: Path) -> None:
    """A nonterminating child is stopped by the process deadline."""
    with pytest.raises(subprocess.TimeoutExpired):
        run_process([sys.executable, '-I', '-c', 'while True: pass'],
                    write_root=tmp_path, environment={}, timeout=0.5)


def test_explicit_environment(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Only explicit Lean settings reach the child, in the requested working directory."""
    monkeypatch.setenv('LEAN_PATH', 'ambient-path')
    result = run_process([sys.executable, '-I', '-c',
                          'import os; print(os.getcwd()); print(os.environ["LEAN_PATH"])'],
                         write_root=tmp_path, environment={'LEAN_PATH': 'selected-path'}, timeout=5)
    assert result.returncode == 0
    assert result.stdout.splitlines() == [str(tmp_path.resolve()), 'selected-path']
