"""Latency diagnostics keep frontend refusals as recorded statuses instead of tracebacks."""

import json
from pathlib import Path
import sys

import pytest

from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.unit


@pytest.mark.parametrize('profile,status', [('invalid', 'INPUT_ERROR'), ('3.99.0', 'UNSUPPORTED')])
def test_trial_records_frontend_refusal(profile: str, status: str, tmp_path: Path) -> None:
    """Run the actual diagnostic in a private process so its recording hooks cannot affect pytest."""
    code = '''import json, runpy, sys
namespace = runpy.run_path(sys.argv[1])
arguments = namespace['CASES'][0].verify_arguments()
arguments[arguments.index('--profile') + 1] = sys.argv[2]
print(json.dumps(namespace['trial'](arguments)))
'''
    result = run_command([sys.executable, '-I', '-c', code,
                          str(ROOT / 'experiments/adr-0003-latency/stage_timing.py'), profile],
                         cwd=tmp_path, timeout=10)
    assert result.returncode == 0, result.diagnostic()
    report = json.loads(result.stdout)
    assert report['status'] == status and report['lean_compiles'] == 0
