"""Retain separate full-validation attempts without changing the development sample policy."""

import argparse
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


def main() -> None:
    """Run one authorized full route; preserve previous attempts and verify every binding."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('route', choices=('native', 'progress'))
    args = parser.parse_args()
    route = args.route
    limit = 900 if route == 'native' else 420
    output = CORE / f'reports/20261002-adr5-review-v5-{route}-linux.json'
    receipt_path = BASE / f'receipts/{route}-{limit}.json'
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise ValueError('Actual Linux amd64 execution is required')
    if output.exists() or receipt_path.exists():
        raise ValueError('Fresh full report and receipt are required')
    sys.path.insert(0, str(CORE))
    from tools.check_resources import check_resources
    check_resources(CORE)
    before = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
    native_receipt = BASE / 'receipts/native-900.json'
    if route == 'progress':
        previous = json.loads(native_receipt.read_text())
        if previous['passed'] is not True or previous['after'] != before:
            raise ValueError('Current full native replay must pass before progress')
    timeout = shutil.which('timeout')
    if timeout is None:
        raise ValueError('Configured timeout command is unavailable')
    arguments = (['-c', validate.NATIVE_CODE, str(CORE / 'conformance/corpus-v5'), str(output)]
        if route == 'native' else ['-m', 'conformance.progress', '--runtime-root', str(validate.RUNTIME), '--output', str(output)])
    command = [timeout, str(limit), str(validate.PYTHON), *arguments]
    environment = {**os.environ, 'PATH': ':'.join(str(path / 'bin') for path in validate.NATIVE_PATHS)
        + ':' + str(validate.RUNTIME / 'build') + ':' + os.environ['PATH'],
        'PYTHONPATH': str(CORE), 'PYTHONDONTWRITEBYTECODE': '1'}
    started = monotonic()
    result = subprocess.run(command, cwd=CORE, env=environment, capture_output=True, text=True, timeout=limit + 5)
    receipt = {'receiptVersion': 1, 'route': route, 'command': command, 'cwd': str(CORE),
        'timeoutSeconds': limit, 'executionPlatform': 'linux/amd64', 'resourceGuard': 'passed',
        'pythonVersion': sys.version, 'attemptHelperSha256': validate.sha(Path(__file__)),
        'seconds': monotonic() - started, 'exitCode': result.returncode,
        'stdout': result.stdout, 'stderr': result.stderr, 'before': before, 'passed': False}
    if route == 'progress':
        receipt['nativeReceiptSha256'] = validate.sha(native_receipt)
    try:
        after = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
        receipt['after'] = after
        receipt['bindingsUnchanged'] = after == before
        if after != before:
            raise ValueError('Source/runtime/input bindings changed')
        if result.returncode != 0:
            raise ValueError('Actual full command failed')
        report = json.loads(output.read_text())
        validate.check_report(route, report, CORE, after)
        receipt.update(report=str(output), reportSha256=validate.sha(output), passed=True,
            denominator=report['denominator'], casesSha256=report['casesSha256'])
        if route == 'progress':
            receipt['counts'] = report['counts']
    except Exception as error:
        receipt['failure'] = str(error)
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt.get(key) for key in ('route', 'seconds', 'exitCode', 'passed',
        'bindingsUnchanged', 'denominator', 'counts', 'failure', 'reportSha256')}), flush=True)
    if receipt['passed'] is not True:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
