"""Compare unchanged native file-backed replay on ordinary /tmp and dedicated tmpfs."""

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
Json = validate.Json


def child(input_path: Path, output: Path) -> None:
    """Run precisely the corpus native_replay record_sql arguments, preserving typed cells."""
    sys.path.insert(0, str(CORE))
    from conformance.execution_profile import recorded_profile
    from conformance.native_record import record_sql
    from conformance.native_replay import decode_rows
    record = json.loads(input_path.read_text())
    profile = recorded_profile(record)
    actual_paths: list[str] = []
    def audit(event: str, arguments: tuple[Json, ...]) -> None:
        """Observe actual native fixture directories without changing their behavior."""
        if event == 'tempfile.mkdtemp' and 'native-corpus-' in str(arguments[0]):
            actual_paths.append(str(arguments[0]))
    sys.addaudithook(audit)
    started = monotonic()
    fresh = record_sql(record['setupCommands'], record['migrationSql'], name=record['name'],
        outputs=True, parameters=decode_rows([event['parameters'] for event in record['trace']]),
        profile=profile, setup_clock=record.get('setupClockUnixMilliseconds'),
        clock_values=[event['clockUnixMilliseconds'] for event in record['trace']]
            if profile.clock == 'unix-milliseconds-v1' else None)
    elapsed = monotonic() - started
    if (fresh['initial'], fresh['trace']) != (record['initial'], record['trace']):
        raise ValueError('Fresh native observations differ from frozen evidence')
    temporary = Path(tempfile.gettempdir())
    if not actual_paths or any(Path(path).parent != temporary for path in actual_paths):
        raise ValueError('Native fixture did not use the declared file-backed temporary root')
    output.write_text(json.dumps({'name': record['name'], 'seconds': elapsed,
        'tmpdir': os.environ['TMPDIR'], 'actualTemporaryRoot': str(temporary),
        'nativeFixturePaths': actual_paths, 'frozenObservationsEqual': True, 'fresh': fresh}) + '\n')


def main() -> None:
    """Select one authored and two distinct-source longest setup prefixes before any timings."""
    if len(sys.argv) == 4 and sys.argv[1] == '--child':
        child(Path(sys.argv[2]), Path(sys.argv[3]))
        return
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise ValueError('Actual Linux amd64 is required')
    sys.path.insert(0, str(CORE))
    from conformance.corpus import load
    from tools.check_resources import check_resources
    check_resources(CORE)
    before = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
    manifest, records = load(CORE / 'conformance/corpus-v5')
    authored = min((record for record in records if 'upstream' not in record),
        key=lambda record: (len(record['setupCommands']), record['name']))
    upstream = sorted((record for record in records if 'upstream' in record),
        key=lambda record: (-len(record['setupCommands']), record['name']))
    selected = [authored]
    sources: set[str] = set()
    for record in upstream:
        source = record['upstream']['file']
        if source not in sources:
            selected.append(record)
            sources.add(source)
        if len(selected) == 3:
            break
    if len(selected) != 3 or shutil.disk_usage('/dev/shm').free < 10 * 1024 ** 3:
        raise ValueError('Three cases and adequate tmpfs free space are required')
    os.umask(0o077)
    attempt = Path(tempfile.mkdtemp(prefix='filesystem-diagnostic-', dir=BASE))
    ordinary = Path(tempfile.mkdtemp(prefix='adr5-native-diagnostic-', dir='/tmp'))
    tmpfs = Path(tempfile.mkdtemp(prefix='adr5-native-diagnostic-', dir='/dev/shm'))
    resources = subprocess.run(['sh', '-c', 'findmnt -T /tmp; findmnt -T /dev/shm; df -B1 /tmp /dev/shm; uptime; free -b'],
        capture_output=True, text=True, check=True, timeout=10).stdout
    receipt: dict[str, Json] = {'diagnosticVersion': 1, 'before': before,
        'helperSha256': validate.sha(Path(__file__)), 'executionPlatform': 'linux/amd64',
        'casesSha256': manifest['casesSha256'], 'resourceGuard': 'passed', 'resources': resources,
        'selectionPolicy': 'shortest authored setup; longest upstream setup from two distinct sources; name breaks ties',
        'directories': {'ordinary': str(ordinary), 'tmpfs': str(tmpfs)}, 'cases': [], 'passed': False}
    environment = {**os.environ, 'PATH': ':'.join(str(path / 'bin') for path in validate.NATIVE_PATHS)
        + ':' + os.environ['PATH'], 'PYTHONPATH': str(CORE), 'PYTHONDONTWRITEBYTECODE': '1'}
    timeout = shutil.which('timeout')
    if timeout is None:
        raise ValueError('Configured timeout is missing')
    try:
        for index, record in enumerate(selected):
            input_path = attempt / f'case-{index}.json'
            input_path.write_text(json.dumps(record) + '\n')
            measurements: dict[str, Json] = {}
            case = {'name': record['name'], 'upstream': record.get('upstream'),
                'setupCommands': len(record['setupCommands']), 'recordSha256': validate.sha(input_path),
                'measurements': measurements, 'fullFreshRecordsEqual': False}
            receipt['cases'].append(case)
            for label, directory in (('ordinary', ordinary), ('tmpfs', tmpfs)):
                output = attempt / f'case-{index}-{label}.json'
                command = [timeout, '60', str(validate.PYTHON), str(Path(__file__)), '--child', str(input_path), str(output)]
                started = monotonic()
                result = subprocess.run(command, cwd=CORE, env={**environment, 'TMPDIR': str(directory)},
                    capture_output=True, text=True, timeout=65)
                measured: dict[str, Json] = {'command': command, 'timeoutSeconds': 60,
                    'seconds': monotonic() - started, 'exitCode': result.returncode,
                    'stdout': result.stdout, 'stderr': result.stderr, 'TMPDIR': str(directory)}
                measurements[label] = measured
                if result.returncode != 0:
                    raise ValueError(f'Paired diagnostic failed: {record["name"]} on {label}')
                payload = json.loads(output.read_text())
                measured.update(recordSqlSeconds=payload['seconds'], nativeFixturePaths=payload['nativeFixturePaths'],
                    outputSha256=validate.sha(output), frozenObservationsEqual=payload['frozenObservationsEqual'])
            ordinary_value = json.loads((attempt / f'case-{index}-ordinary.json').read_text())
            tmpfs_value = json.loads((attempt / f'case-{index}-tmpfs.json').read_text())
            if ordinary_value['fresh'] != tmpfs_value['fresh']:
                raise ValueError('Full fresh native records differ across file-backed paths')
            case['fullFreshRecordsEqual'] = True
            print(json.dumps(case), flush=True)
        after = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
        receipt.update(after=after, bindingsUnchanged=after == before, passed=after == before)
        if after != before:
            raise ValueError('Source/runtime/native inputs changed')
    except Exception as error:
        receipt['failure'] = str(error)
    finally:
        after = validate.source_binding(CORE, BASE / 'snapshot.json', COMMIT)
        receipt.update(after=after, bindingsUnchanged=after == before)
        output = attempt / 'receipt.json'
        output.write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps({'receipt': str(output), 'sha256': validate.sha(output), 'passed': receipt['passed'],
            'failure': receipt.get('failure')}), flush=True)
    if receipt['passed'] is not True:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
