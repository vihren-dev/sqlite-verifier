"""Run independent full model progress without implying full-native completion."""

import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from time import monotonic

import validate

CORE = Path('/tmp/adr5-review-final.hcG6eK/core')
BASE = CORE.parent
COMMIT = 'fe116b8744c7825529ec8eee21c33f15684a0694'
OUTPUT = CORE / 'reports/20261002-adr5-review-v5-progress-linux.json'
RECEIPT = BASE / 'receipts/progress-independent.json'


def main() -> None:
    """Retain strict timing, exit/result truth and source bindings for this independent classification route."""
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise ValueError('Actual Linux amd64 execution is required')
    if OUTPUT.exists() or RECEIPT.exists():
        raise ValueError('Fresh progress output and receipt are required')
    sys.path.insert(0, str(CORE))
    from tools.check_resources import check_resources
    check_resources(CORE)
    before = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
    timeout = shutil.which('timeout')
    if timeout is None:
        raise ValueError('Configured timeout command is unavailable')
    command = [timeout, '420', str(validate.PYTHON), '-m', 'conformance.progress',
        '--runtime-root', str(validate.RUNTIME), '--output', str(OUTPUT)]
    environment = {**os.environ, 'PATH': ':'.join(str(path / 'bin') for path in validate.NATIVE_PATHS)
        + ':' + str(validate.RUNTIME / 'build') + ':' + os.environ['PATH'],
        'PYTHONPATH': str(CORE), 'PYTHONDONTWRITEBYTECODE': '1'}
    started = monotonic()
    result = subprocess.run(command, cwd=CORE, env=environment, capture_output=True, text=True, timeout=425)
    receipt = {'receiptVersion': 1, 'route': 'progress', 'independentAttempt': True,
        'fullNativeReplayCompleted': False, 'command': command, 'cwd': str(CORE),
        'timeoutSeconds': 420, 'executionPlatform': 'linux/amd64', 'resourceGuard': 'passed',
        'pythonVersion': sys.version, 'attemptHelperSha256': validate.sha(Path(__file__)),
        'seconds': monotonic() - started, 'exitCode': result.returncode,
        'stdout': result.stdout, 'stderr': result.stderr, 'before': before, 'passed': False}
    try:
        after = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
        receipt['after'] = after
        receipt['bindingsUnchanged'] = after == before
        if after != before:
            raise ValueError('Source/runtime/input bindings changed')
        if result.returncode != 0:
            raise ValueError('Actual full progress command failed')
        report = json.loads(OUTPUT.read_text())
        validate.check_report('progress', report, CORE, after)
        receipt.update(report=str(OUTPUT), reportSha256=validate.sha(OUTPUT), passed=True,
            denominator=report['denominator'], counts=report['counts'], requirementMatrixRows=report['requirementMatrixRows'])
    except Exception as error:
        receipt['failure'] = str(error)
    RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt.get(key) for key in ('seconds', 'exitCode', 'passed',
        'bindingsUnchanged', 'denominator', 'requirementMatrixRows', 'counts', 'failure')}), flush=True)
    if receipt['passed'] is not True:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
