"""Recheck retained storage evidence against the original public source and frozen corpus."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

#: The retained experiment contains one authored case and two distinct upstream sources.
EXPECTED_PAIRED_CASES = 3


def digest(path: Path) -> str:
    """Bind retained evidence to its exact bytes before decoding its observations."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    """Require exact identities, native observations, paired fresh records and execution bindings."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    base = Path(__file__).resolve().parent
    source = args.source_root.resolve()
    sys.path.insert(0, str(source))
    from conformance.case_format import Json
    from conformance.corpus import load
    for name, expected in json.loads((base / 'sha256.json').read_text()).items():
        if digest(base / name) != expected:
            raise ValueError('Retained evidence bytes changed: ' + name)
    receipt = json.loads((base / 'linux/receipt.json').read_text())
    report = json.loads((base / 'linux/full.json').read_text())
    manifest, records = load(source / 'conformance/corpus-v5')
    if (not receipt['passed'] or not receipt['bindingsUnchanged']
            or receipt['bindingsBefore'] != receipt['bindingsAfter']
            or receipt['casesSha256'] != report['casesSha256']
            or report['casesSha256'] != manifest['casesSha256']
            or report['denominator'] != receipt['denominator'] or report['denominator'] != len(records)
            or len(receipt['cases']) != EXPECTED_PAIRED_CASES
            or receipt['full']['exitCode'] != 0
            or not 0 < receipt['full']['seconds'] < receipt['full']['timeoutSeconds']
            or [case['name'] for case in report['cases']] != [record['name'] for record in records]):
        raise ValueError('Full replay identities or binding completion differ')
    native = report['nativeReplay']
    audit = native['temporaryStorage']
    if (not native['passed'] or not native['bindingsUnchanged']
            or native['bindingsBefore'] != native['bindingsAfter']
            or audit['fixtureCount'] != len(records) or len(audit['fixturePaths']) != len(records)
            or any(Path(path).parent.parent != Path(audit['selectedRoot']) for path in audit['fixturePaths'])):
        raise ValueError('Native replay completion or actual file paths differ')
    for index, case in enumerate(receipt['cases']):
        original = json.loads(gzip.decompress((base / f'linux/case-{index}.json.gz').read_bytes()))
        fresh: list[dict[str, Json]] = []
        for storage in ('ordinary', 'tmpfs'):
            output = base / f'linux/case-{index}-{storage}.json.gz'
            value = json.loads(gzip.decompress(output.read_bytes()))
            measured = case['measurements'][storage]
            if (digest(output) != case['measurements'][storage]['outputSha256']
                    or measured['exitCode'] != 0 or not 0 < measured['seconds'] < measured['timeoutSeconds']
                    or not value['frozenObservationsEqual']
                    or (value['fresh']['initial'], value['fresh']['trace']) != (original['initial'], original['trace'])
                    or value['fresh']['profile'] != original['profile']
                    or value['fresh']['sourceId'] != original['sourceId']):
                raise ValueError('Retained fresh native observation differs: ' + case['name'])
            fresh.append(value['fresh'])
        if fresh[0] != fresh[1] or not case['fullFreshRecordsEqual']:
            raise ValueError('Complete paired fresh native records differ: ' + case['name'])
    for name, expected in native['bindingsBefore']['sourcesSha256'].items():
        if digest(source / name) != expected:
            raise ValueError('Select the original execution source; file differs: ' + name)
    print(json.dumps({'verified': True, 'denominator': len(records), 'pairedCases': len(receipt['cases'])}))


if __name__ == '__main__':
    main()
