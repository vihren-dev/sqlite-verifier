"""Run only owner-approved final Darwin routes and retain truthful source-bound receipts."""

import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from time import monotonic
from typing import TypeAlias, Union

Json: TypeAlias = Union[None, bool, int, float, str, list['Json'], dict[str, 'Json']]
RUNTIME = Path('/nix/store/2pm5l48v8lk5v3p1yqbc3hx3jj1w2ylr-sqlite-verifier-conformance')
NATIVE = Path('/nix/store/snlk5qqf7gbjk465rrwzxsn14mx3znh0-sqlite-verifier-native-3.51.0')
NATIVE_PATHS = (NATIVE, Path('/nix/store/p46a330qv8pc3cfs5hsskknmk09f6gzk-sqlite-verifier-native-3.46.0'),
    Path('/nix/store/2z8rrsyzds56xr2pafijvqvdacg0s35c-sqlite-verifier-native-3.53.4'))
PYTHON = Path('/nix/store/7xgkr19ify5wzfj8mafjqhywzvsmgqaq-python3-3.14.7-env/bin/python3')
RUNTIME_FILES = ('build/sqlite-parser', '.lake/build/bin/conformance-runner')
NATIVE_CODE = '''from pathlib import Path
import hashlib,json,sys
from conformance.corpus import load,native_replay
from conformance.native_storage import serialized
manifest,records=load(Path(sys.argv[1]))
native_replay(records)
result={"corpusVersion":manifest["corpusVersion"],"casesSha256":manifest["casesSha256"],
"denominator":len(records),"executionProfiles":manifest["executionProfiles"],
"caseNamesSha256":hashlib.sha256(serialized([r["name"] for r in records])).hexdigest(),
"nativeReplayPassed":True}
Path(sys.argv[2]).write_text(json.dumps(result,indent=2)+"\\n")
'''


def sha(path: Path) -> str:
    """Bind actual bytes rather than path names."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_binding(core: Path, snapshot: Path, commit: str) -> dict[str, Json]:
    """Refuse a missing/stale tracked file, commit or runtime before and after execution."""
    metadata = json.loads(snapshot.read_text())
    if metadata['sourceCommit'] != commit or len(commit) != 40:
        raise ValueError('Final source commit differs')
    for name, expected in metadata['sourceFilesSha256'].items():
        path = core / name
        if path.is_symlink() or not path.is_file() or sha(path) != expected:
            raise ValueError('Final tracked source changed: ' + name)
    if any(not os.access(RUNTIME / name, os.X_OK) for name in RUNTIME_FILES):
        raise ValueError('Built runtime is unavailable')
    return {'sourceCommit': commit, 'snapshotSha256': sha(snapshot), 'core': str(core),
        'helperSha256': sha(Path(__file__)), 'pythonSha256': sha(PYTHON),
        'runtime': str(RUNTIME), 'runtimeSha256': {name: sha(RUNTIME / name) for name in RUNTIME_FILES},
        'nativeSha256': {str(path): sha(path) for directory in NATIVE_PATHS for path in
            sorted((directory / 'bin').iterdir()) + [directory / 'lib/libsqlite3.dylib']},
        'harnessSha256': {path.name: sha(path) for path in sorted((core / 'conformance').glob('*.py'))},
        'frontendSha256': {str(path.relative_to(core)): sha(path) for path in sorted((core / 'migration_check').glob('*.py'))},
        'genericManifestSha256': sha(core / 'conformance/corpus-v5/manifest.json'),
        'syntheticInventorySha256': sha(core / 'conformance/synthetic-workload/workload.json')}


def checked_counts(report: dict[str, Json], names: list[str]) -> None:
    """Unsupported remains visible; a successful CLI alone cannot prove agreement."""
    cases = report['cases']
    if [case['name'] for case in cases] != names:
        raise ValueError('Report case identities differ')
    counts = dict(Counter(case['verdict'] for case in cases))
    if any(verdict not in {'AGREE', 'DISAGREE', 'MODEL_UNSUPPORTED', 'HARNESS_ERROR'} for verdict in counts):
        raise ValueError('Unknown verdict')
    if (not isinstance(report['counts'], dict) or any(type(value) is not int or value < 0 for value in report['counts'].values())
            or report['counts'] != counts or {'DISAGREE', 'HARNESS_ERROR'} & counts.keys()):
        raise ValueError('Report verdicts failed or differ')


def check_report(route: str, report: dict[str, Json], core: Path, binding: dict[str, Json]) -> None:
    """Validate real report accounting against the ordinarily verified frozen inputs."""
    from conformance.corpus import load
    from conformance.native_storage import serialized
    from conformance.replay_tiers import AUTHORED_PARTS, select
    from conformance.workload import bound_records
    manifest, records = load(core / 'conformance/corpus-v5')
    names = [record['name'] for record in records]
    if route in {'native', 'progress'}:
        if (report['corpusVersion'] != 5 or report['casesSha256'] != manifest['casesSha256']
                or type(report['denominator']) is not int or report['denominator'] != len(records)):
            raise ValueError('Full report corpus binding differs')
        if route == 'native':
            if (report['nativeReplayPassed'] is not True or report['executionProfiles'] != manifest['executionProfiles']
                    or report['caseNamesSha256'] != hashlib.sha256(serialized(names)).hexdigest()):
                raise ValueError('Native report does not cover every case')
            return
        checked_counts(report, names)
        if (report['runtimeSha256'] != binding['runtimeSha256'] or report['harnessSha256'] != binding['harnessSha256']
                or report['frontendSha256'] != binding['frontendSha256'] or report['corpusManifestSha256'] != binding['genericManifestSha256']
                or report['requirementMatrixRows'] != 3500 or len(report['requirementMatrix']) != 3500
                or sum(row['denominator'] for row in report['byShard']) != len(records)):
            raise ValueError('Progress runtime/inventory/shard binding differs')
        return
    synthetic = core / 'conformance/synthetic-workload'
    synthetic_manifest, synthetic_records = bound_records(synthetic, synthetic / 'corpus')
    selected = select(records)
    if report['generic']['manifestSha256'] != binding['genericManifestSha256']:
        raise ValueError('Sample manifest binding differs')
    if {item['path']: item['sha256'] for item in report['runtime'].values()} != binding['runtimeSha256']:
        raise ValueError('Sample runtime binding differs')
    if sum(record['part'] in AUTHORED_PARTS for record in selected) != 69 or len(synthetic_records) != 2:
        raise ValueError('Sample mandatory membership differs')
    for label, declaration, actual in (('generic', manifest, selected), ('synthetic', synthetic_manifest, synthetic_records)):
        section = report[label]
        if section['nativeReplayPassed'] is not True or section['casesSha256'] != declaration['casesSha256']:
            raise ValueError('Sample fresh native/corpus binding differs')
        checked_counts(section, [record['name'] for record in actual])
    if report['counts'] != dict(Counter(report['generic']['counts']) + Counter(report['synthetic']['counts'])):
        raise ValueError('Sample aggregate counts differ')
    measured = report['measurement']['seconds']
    if (type(measured) not in {float, int} or not math.isfinite(measured) or not 0 < measured < 60
            or report['measurement']['limitSeconds'] != 60 or report['selectedDenominator'] != len(selected) + 2):
        raise ValueError('Sample timing/denominator differs')


def main() -> None:
    """Require the final commit and new receipt destination; never overwrite earlier evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core', type=Path, required=True)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--receipts', type=Path, required=True)
    args = parser.parse_args()
    core, snapshot = args.core.resolve(), args.snapshot.resolve()
    sys.path.insert(0, str(core))
    from conformance.corpus import load
    from tools.check_resources import check_resources
    if (platform.system(), platform.machine()) != ('Darwin', 'arm64'):
        raise ValueError('Actual macOS arm64 execution is required')
    check_resources(core)
    before = source_binding(core, snapshot, args.commit)
    manifest, records = load(core / 'conformance/corpus-v5')
    if type(manifest['corpusVersion']) is not int or manifest['corpusVersion'] != 5 or any(record['nativeVersion'] != 4 for record in records):
        raise ValueError('Final v5 native4 corpus is required')
    reports = {route: core / f'reports/20261002-adr5-review-v5-{route}-darwin.json' for route in ('native', 'sample', 'progress')}
    if any(path.exists() for path in reports.values()) or args.receipts.exists():
        raise ValueError('Final evidence destination already exists')
    args.receipts.mkdir(parents=True)
    environment = {**os.environ, 'PATH': ':'.join(str(path / 'bin') for path in NATIVE_PATHS) + ':' + str(RUNTIME / 'build') + ':' + os.environ['PATH'],
        'PYTHONPATH': str(core), 'PYTHONDONTWRITEBYTECODE': '1'}
    timeout = shutil.which('timeout')
    if timeout is None:
        raise ValueError('Configured timeout executable is unavailable')
    for route, limit in (('native', 420), ('sample', 60), ('progress', 420)):
        output = reports[route]
        arguments = (['-c', NATIVE_CODE, str(core / 'conformance/corpus-v5'), str(output)] if route == 'native'
            else ['-m', 'conformance.' + ('replay_tiers' if route == 'sample' else 'progress'), '--runtime-root', str(RUNTIME), '--output', str(output)])
        command = [timeout, str(limit), str(PYTHON), *arguments]
        started = monotonic()
        result = subprocess.run(command, cwd=core, env=environment, capture_output=True, text=True, timeout=limit + 5)
        receipt = {'receiptVersion': 1, 'route': route, 'command': command, 'cwd': str(core), 'timeoutSeconds': limit,
            'executionPlatform': 'darwin/arm64', 'resourceGuard': 'passed', 'pythonVersion': sys.version, 'seconds': monotonic() - started, 'exitCode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr, 'before': before, 'passed': False}
        try:
            if result.returncode != 0:
                raise ValueError('Actual command failed')
            after = source_binding(core, snapshot, args.commit)
            if after != before:
                raise ValueError('Source/runtime/input bindings changed during execution')
            check_report(route, json.loads(output.read_text()), core, after)
            receipt.update(after=after, report=str(output), reportSha256=sha(output), passed=True)
        except Exception as error:
            receipt['failure'] = str(error)
            raise
        finally:
            (args.receipts / (route + '.json')).write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps({key: receipt[key] for key in ('route', 'seconds', 'passed', 'reportSha256')}), flush=True)


if __name__ == '__main__':
    main()
