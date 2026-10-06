"""Rebinding the gzip inventory cannot excuse a changed executed native report."""

import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sys

import pytest

from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance]


def test_changed_native_report_cannot_be_rebound_to_the_byte_inventory(tmp_path: Path) -> None:
    """A changed raw report must fail its original execution receipt even after rebinding compressed bytes."""
    packet = tmp_path / 'packet'
    shutil.copytree(ROOT / 'reports/20261006-native-replay-storage', packet,
                    ignore=shutil.ignore_patterns('__pycache__'))
    report = packet / 'linux/full.json.gz'
    report.write_bytes(gzip.compress(gzip.decompress(report.read_bytes()) + b'\n', mtime=0))
    inventory = json.loads((packet / 'sha256.json').read_text())
    inventory['linux/full.json.gz'] = hashlib.sha256(report.read_bytes()).hexdigest()
    (packet / 'sha256.json').write_text(json.dumps(inventory))
    result = run_command([sys.executable, str(packet / 'validate.py'), '--source-root', str(ROOT)],
                         cwd=ROOT, timeout=10)
    assert result.returncode == 1 and 'Full report bytes in' in result.stderr, result.diagnostic()
    assert 'restore the report from its commit' in result.stderr, result.diagnostic()
