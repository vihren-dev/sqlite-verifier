"""Retain three paired Linux filesystem comparisons and one bounded full native replay."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
from time import monotonic

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from conformance.case_format import Json
from conformance.corpus import load
from conformance.execution_profile import recorded_profile
from conformance.native_record import record_sql
from conformance.native_replay import decode_rows
from conformance.native_replay_report import bindings, storage_resources
from conformance.native_storage import serialized
from tools.check_resources import check_resources

#: Select representatives from frozen inputs before observing any timings.
SELECTION_POLICY = 'shortest authored setup; longest upstream setup from two distinct sources; name breaks ties'
#: One authored case and two different upstream sources retain the historical comparison denominator.
REPRESENTATIVE_CASE_COUNT = 3
#: Match the retained diagnostic and full-run bounds from issue #37.
CASE_TIMEOUT_SECONDS = 60
FULL_TIMEOUT_SECONDS = 420
#: Leave the existing five-second receipt grace after the external timeout has stopped its child.
RECEIPT_GRACE_SECONDS = 5


def write(path: Path, value: dict[str, Json]) -> None:
    """Keep complete records compactly, with deterministic gzip metadata and no overwritten evidence."""
    with path.open('xb') as output:
        output.write(gzip.compress(serialized(value), mtime=0))


def child(input_path: Path, storage: Path, output: Path) -> None:
    """Use precisely the native replay arguments and retain complete fresh records and actual file paths."""
    record = json.loads(gzip.decompress(input_path.read_bytes()))
    profile = recorded_profile(record)
    paths: list[Path] = []
    started = monotonic()
    fresh = record_sql(record['setupCommands'], record['migrationSql'], name=record['name'],
        outputs=True, parameters=decode_rows([event['parameters'] for event in record['trace']]),
        profile=profile, setup_clock=record.get('setupClockUnixMilliseconds'),
        clock_values=[event['clockUnixMilliseconds'] for event in record['trace']]
            if profile.clock == 'unix-milliseconds-v1' else None,
        temporary_root=storage, fixture_paths=paths)
    elapsed = monotonic() - started
    if (fresh['initial'], fresh['trace']) != (record['initial'], record['trace']):
        raise ValueError('Fresh native observations differ from frozen evidence')
    if len(paths) != 1 or paths[0].parent.parent != storage or paths[0].parent.exists():
        raise ValueError('Native fixture path or cleanup differs from the selected ordinary-file root')
    write(output, {'name': record['name'], 'seconds': elapsed, 'fresh': fresh,
        'fixturePaths': [str(path) for path in paths], 'frozenObservationsEqual': True,
        'temporaryStorage': storage_resources(storage)})


def resources(directory: Path, expected: str) -> dict[str, Json]:
    """Verify the actual filesystem and retain capacity and host memory/load conditions."""
    command = ['findmnt', '-n', '-o', 'FSTYPE,TARGET,SOURCE', '-T', str(directory)]
    mount = subprocess.run(command, capture_output=True, text=True, check=True, timeout=5).stdout
    if mount.split()[0] != expected:
        raise ValueError(f'Expected {expected} for {directory}, found {mount.strip()}')
    return {**storage_resources(directory), 'mountCommand': command, 'mount': mount,
        'uptime': subprocess.run(['uptime'], capture_output=True, text=True, check=True, timeout=5).stdout,
        'memory': subprocess.run(['free', '-b'], capture_output=True, text=True, check=True, timeout=5).stdout}


def main() -> None:
    """Run serial measurements on fresh paths; always retain a terminal receipt if a measured phase fails."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child', type=Path)
    parser.add_argument('--storage', type=Path)
    parser.add_argument('--corpus', type=Path, default=ROOT / 'conformance/corpus-v5')
    parser.add_argument('--runtime-root', type=Path)
    parser.add_argument('--ordinary-root', type=Path)
    parser.add_argument('--tmpfs-root', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.child is not None:
        if args.storage is None:
            parser.error('--child requires --storage')
        child(args.child, args.storage.resolve(), args.output)
        return
    if any(path is None for path in (args.runtime_root, args.ordinary_root, args.tmpfs_root)):
        parser.error('Measurements require --runtime-root, --ordinary-root and --tmpfs-root')
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        parser.error('Run measurements on an actual Linux x86_64 host')
    ordinary, tmpfs = args.ordinary_root.resolve(), args.tmpfs_root.resolve()
    for directory in (ordinary, tmpfs):
        check_resources(ROOT, temporary_root=directory)
    args.output.mkdir()
    manifest, records = load(args.corpus)
    before = bindings(args.corpus, records, args.runtime_root)
    authored = min((record for record in records if 'upstream' not in record),
                   key=lambda record: (len(record['setupCommands']), record['name']))
    selected = [authored]
    sources: set[str] = set()
    for record in sorted((record for record in records if 'upstream' in record),
                         key=lambda record: (-len(record['setupCommands']), record['name'])):
        if record['upstream']['file'] not in sources:
            selected.append(record)
            sources.add(record['upstream']['file'])
        if len(selected) == REPRESENTATIVE_CASE_COUNT:
            break
    if len(selected) != REPRESENTATIVE_CASE_COUNT:
        raise ValueError('Three deterministic representative cases are required')
    helper_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    receipt: dict[str, Json] = {'receiptVersion': 1, 'passed': False, 'command': list(sys.orig_argv),
        'platform': platform.platform(), 'pythonVersion': sys.version, 'helperSha256': helper_hash,
        'casesSha256': manifest['casesSha256'], 'denominator': len(records), 'bindingsBefore': before,
        'selectionPolicy': SELECTION_POLICY, 'resources': {
            'ordinary': resources(ordinary, 'ext4'), 'tmpfs': resources(tmpfs, 'tmpfs')}, 'cases': []}
    try:
        for index, record in enumerate(selected):
            input_path = args.output / f'case-{index}.json.gz'
            write(input_path, record)
            measured: dict[str, Json] = {'name': record['name'], 'upstream': record.get('upstream'),
                'setupCommands': len(record['setupCommands']), 'inputSha256': hashlib.sha256(input_path.read_bytes()).hexdigest(),
                'measurements': {}, 'fullFreshRecordsEqual': False}
            receipt['cases'].append(measured)
            fresh: list[dict[str, Json]] = []
            for label, storage in (('ordinary', ordinary), ('tmpfs', tmpfs)):
                output = args.output / f'case-{index}-{label}.json.gz'
                command = ['timeout', str(CASE_TIMEOUT_SECONDS), sys.executable, str(Path(__file__)), '--child', str(input_path),
                           '--storage', str(storage), '--output', str(output)]
                started = monotonic()
                result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                        timeout=CASE_TIMEOUT_SECONDS + RECEIPT_GRACE_SECONDS)
                observation: dict[str, Json] = {'command': command, 'timeoutSeconds': CASE_TIMEOUT_SECONDS,
                    'seconds': monotonic() - started, 'exitCode': result.returncode,
                    'stdout': result.stdout, 'stderr': result.stderr}
                measured['measurements'][label] = observation
                if result.returncode:
                    raise ValueError(f'Paired native replay failed for {record["name"]} on {label}')
                value = json.loads(gzip.decompress(output.read_bytes()))
                fresh.append(value['fresh'])
                observation.update(recordSqlSeconds=value['seconds'], fixturePaths=value['fixturePaths'],
                    outputSha256=hashlib.sha256(output.read_bytes()).hexdigest(), frozenObservationsEqual=True)
            if fresh[0] != fresh[1]:
                raise ValueError('Complete fresh native records differ between ext4 and tmpfs')
            measured['fullFreshRecordsEqual'] = True
            print(json.dumps(measured), flush=True)
        command = ['timeout', str(FULL_TIMEOUT_SECONDS), sys.executable, '-m', 'conformance.corpus', str(args.corpus),
                   '--runtime-root', str(args.runtime_root), '--native-check', '--temporary-root', str(tmpfs),
                   '--output', str(args.output / 'full.json')]
        started = monotonic()
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                timeout=FULL_TIMEOUT_SECONDS + RECEIPT_GRACE_SECONDS)
        receipt['full'] = {'command': command, 'timeoutSeconds': FULL_TIMEOUT_SECONDS, 'seconds': monotonic() - started,
                          'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
        if result.returncode:
            raise ValueError('Bounded full native replay did not complete successfully')
        report = json.loads((args.output / 'full.json').read_text())
        if (report['casesSha256'] != manifest['casesSha256'] or report['denominator'] != len(records)
                or [case['name'] for case in report['cases']] != [record['name'] for record in records]
                or not report['nativeReplay']['passed'] or not report['nativeReplay']['bindingsUnchanged']):
            raise ValueError('Full native report identities or completion differ')
        receipt['full']['reportSha256'] = hashlib.sha256((args.output / 'full.json').read_bytes()).hexdigest()
        receipt['passed'] = True
    except Exception as error:
        receipt['failure'] = str(error)
    finally:
        after = bindings(args.corpus, records, args.runtime_root)
        receipt.update(bindingsAfter=after, bindingsUnchanged=before == after)
        if before != after or helper_hash != hashlib.sha256(Path(__file__).read_bytes()).hexdigest():
            receipt.update(passed=False, failure='Source, corpus, runtime, native or helper bindings changed')
        (args.output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps({'passed': receipt['passed'], 'failure': receipt.get('failure')}), flush=True)
    if not receipt['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
