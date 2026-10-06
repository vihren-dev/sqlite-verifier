"""Run one unchanged full native replay on disclosed ordinary files in dedicated tmpfs."""

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
from time import monotonic

import validate

CORE = Path('/tmp/adr5-review-final.hcG6eK/core')
BASE = CORE.parent
COMMIT = 'fe116b8744c7825529ec8eee21c33f15684a0694'
OUTPUT = CORE / 'reports/20261002-adr5-review-v5-native-linux.json'
RECEIPT = BASE / 'receipts/native-tmpfs-420.json'
PREFIX = '''import os,tempfile
fixture_paths=[]
def observe_temporary(event,arguments):
    if event == "tempfile.mkdtemp" and "native-corpus-" in str(arguments[0]):
        fixture_paths.append(str(arguments[0]))
import sys
sys.addaudithook(observe_temporary)
'''
SUFFIX = '''
if len(fixture_paths) != len(records) or any(Path(path).parent != Path(os.environ["TMPDIR"]) for path in fixture_paths):
    raise ValueError("Actual native temporary fixture paths differ")
result.update(temporaryStorage={"TMPDIR":os.environ["TMPDIR"],"actualTemporaryRoot":tempfile.gettempdir(),
    "fixtureCount":len(fixture_paths),"firstFixture":fixture_paths[0],"lastFixture":fixture_paths[-1],
    "allFixturesBeneathDeclaredRoot":True,"databaseKind":"ordinary-file"})
Path(sys.argv[2]).write_text(json.dumps(result,indent=2)+"\\n")
'''


def main() -> None:
    """Require actual paired equality before the single authorized bounded attempt."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--diagnostic-receipt', type=Path, required=True)
    args = parser.parse_args()
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise ValueError('Actual Linux amd64 is required')
    if OUTPUT.exists() or RECEIPT.exists():
        raise ValueError('Fresh native report and receipt are required')
    sys.path.insert(0, str(CORE))
    from tools.check_resources import check_resources
    check_resources(CORE)
    before = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
    diagnostic = json.loads(args.diagnostic_receipt.read_text())
    if (diagnostic['passed'] is not True or diagnostic['after'] != before or len(diagnostic['cases']) != 3
            or any(case['fullFreshRecordsEqual'] is not True for case in diagnostic['cases'])):
        raise ValueError('Current paired file-backed diagnostic must pass first')
    if shutil.disk_usage('/dev/shm').free < 10 * 1024 ** 3:
        raise ValueError('Dedicated tmpfs requires at least 10 GiB free')
    os.umask(0o077)
    temporary = Path(tempfile.mkdtemp(prefix='adr5-full-native-', dir='/dev/shm'))
    resources = subprocess.run(['sh', '-c', 'findmnt -T /dev/shm; df -B1 /dev/shm; uptime; free -b'],
        capture_output=True, text=True, check=True, timeout=10).stdout
    timeout = shutil.which('timeout')
    if timeout is None:
        raise ValueError('Configured timeout is missing')
    command = [timeout, '420', str(validate.PYTHON), '-c', PREFIX + validate.NATIVE_CODE + SUFFIX,
        str(CORE / 'conformance/corpus-v5'), str(OUTPUT)]
    environment = {**os.environ, 'PATH': ':'.join(str(path / 'bin') for path in validate.NATIVE_PATHS)
        + ':' + str(validate.RUNTIME / 'build') + ':' + os.environ['PATH'],
        'PYTHONPATH': str(CORE), 'PYTHONDONTWRITEBYTECODE': '1', 'TMPDIR': str(temporary)}
    started = monotonic()
    result = subprocess.run(command, cwd=CORE, env=environment, capture_output=True, text=True, timeout=425)
    receipt = {'receiptVersion': 1, 'route': 'native', 'command': command, 'cwd': str(CORE),
        'timeoutSeconds': 420, 'executionPlatform': 'linux/amd64', 'resourceGuard': 'passed',
        'pythonVersion': sys.version, 'attemptHelperSha256': validate.sha(Path(__file__)),
        'diagnosticReceipt': str(args.diagnostic_receipt), 'diagnosticReceiptSha256': validate.sha(args.diagnostic_receipt),
        'environmentOverrides': {'TMPDIR': str(temporary)}, 'temporaryFilesystem': resources,
        'databaseKind': 'ordinary-file', 'seconds': monotonic() - started, 'exitCode': result.returncode,
        'stdout': result.stdout, 'stderr': result.stderr, 'before': before, 'passed': False}
    try:
        after = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
        receipt.update(after=after, bindingsUnchanged=after == before)
        if after != before or result.returncode != 0:
            raise ValueError('Full native attempt failed or its bindings changed')
        report = json.loads(OUTPUT.read_text())
        validate.check_report('native', report, CORE, after)
        receipt.update(report=str(OUTPUT), reportSha256=validate.sha(OUTPUT), passed=True,
            denominator=report['denominator'], casesSha256=report['casesSha256'],
            temporaryStorage=report['temporaryStorage'])
    except Exception as error:
        receipt['failure'] = str(error)
    RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt.get(key) for key in ('seconds', 'exitCode', 'passed', 'bindingsUnchanged',
        'denominator', 'casesSha256', 'temporaryStorage', 'reportSha256', 'failure')}), flush=True)
    if receipt['passed'] is not True:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
