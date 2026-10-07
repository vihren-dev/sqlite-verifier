"""Validate the retained isolated build and hosted failures without executing their helpers."""

import gzip
import hashlib
import json
from pathlib import Path
from typing import NoReturn, TypeAlias
import xml.etree.ElementTree as ET

Json: TypeAlias = None | bool | int | float | str | list['Json'] | dict[str, 'Json']
RAW_MANIFEST_SHA256 = '1c1408859f1d7299d101899b7ac3b669e25a30cae18a0f81da7a51f2de23445f'
"""Bind all sixteen original observations, including the earlier whole-suite failures."""
RETAINED_PAYLOAD_COUNT = 16
"""Retain twelve isolated observations, their digest manifest, one helper and two hosted failure logs."""
ORIGINAL_PAYLOAD_COUNT = 12
"""The isolated observer's original digest manifest binds twelve observations."""
BUNDLE_CASE_COUNT = 42
"""The unchanged complete bundle gate has forty-two cases and no skipped cases."""
BUNDLE_TEST_FILES = ('tests/bundle_test.py', 'tests/proof_exporter_test.py',
                     'tests/stage_reuse_test.py', 'tests/generated_inputs_test.py')
"""The isolated build retains the exact four-file bundle gate from the failed derivation."""


def fail(where: str) -> NoReturn:
    """Name the failed observation and the retained evidence needed to investigate it."""
    raise ValueError(f'{where} differs. Compare raw-sha256.json, the retained gzip files and the original receipts.')


def check(condition: bool, where: str) -> None:
    """Keep evidence checks active even when Python assertions are disabled."""
    if not condition:
        fail(where)


def digest(payload: bytes) -> str:
    """Compare original bytes independently of compressed transport."""
    return hashlib.sha256(payload).hexdigest()


def document(payload: bytes, name: str) -> dict[str, Json]:
    """Require object-shaped observations and identify malformed retained JSON."""
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise ValueError(f'{name} has invalid JSON. Compare its retained gzip bytes with the original receipt.') from error
    if not isinstance(value, dict):
        fail(name + ' object shape')
    return value


def validate(root: Path) -> None:
    """Require exact retained evidence, complete passing cases and unchanged identities."""
    manifest_bytes = (root / 'raw-sha256.json').read_bytes()
    check(digest(manifest_bytes) == RAW_MANIFEST_SHA256, 'raw-sha256.json digest')
    manifest = document(manifest_bytes, 'raw-sha256.json')
    check(len(manifest) == RETAINED_PAYLOAD_COUNT, 'raw-sha256.json payload count')
    raw: dict[str, bytes] = {}
    for name, entry in manifest.items():
        if not isinstance(entry, dict) or not isinstance(entry.get('gzip'), str):
            fail(name + ' compressed binding')
        compressed = (root / entry['gzip']).read_bytes()
        check(digest(compressed) == entry['gzipSha256'], entry['gzip'] + ' digest')
        payload = gzip.decompress(compressed)
        check(len(payload) == entry['bytes'] and digest(payload) == entry['sha256'], name + ' original bytes')
        raw[name] = payload
    original = document(raw['raw-sha256.json'], 'original raw-sha256.json')
    check(len(original) == ORIGINAL_PAYLOAD_COUNT, 'original raw-sha256.json payload count')
    for name, entry in original.items():
        if not isinstance(entry, dict):
            fail(name + ' original binding')
        check(len(raw[name]) == entry['bytes'] and digest(raw[name]) == entry['sha256'], name + ' isolated bytes')
    before, after = (document(raw[name], name) for name in ('identity-before.json', 'identity-after.json'))
    check(before == after, 'identity-before.json and identity-after.json')
    for role, name in (('observer', 'observe.py'), ('metadataHelper', 't04c_metadata.py'),
                       ('derivation', 'exact-derivation.drv')):
        binding = before[role]
        check(isinstance(binding, dict) and digest(raw[name]) == binding['sha256'], name + ' identity')
    preflight, result = (document(raw[name], name) for name in ('preflight.json', 'build-result.json'))
    declaration = preflight['declaration']
    if not isinstance(declaration, dict) or not isinstance(declaration.get('installPhase'), str):
        fail('preflight.json installPhase')
    command = declaration['installPhase']
    check('timeout 420 python3 -m pytest ' + ' '.join(BUNDLE_TEST_FILES) in command, 'bundle suite command')
    check('PYTEST_DISABLE_PLUGIN_AUTOLOAD=1' in command and '-p no:cacheprovider' in command, 'bundle plugin flags')
    check(preflight['previousValidityExit'] == 1 and preflight['outputExisted'] is False, 'preflight.json output validity')
    check(result['returncode'] == 0 and result['timedOut'] is False, 'build-result.json exit and timeout')
    started, ended = result['started'], result['ended']
    if not isinstance(started, dict) or not isinstance(ended, dict):
        fail('build-result.json boundaries')
    if not isinstance(started.get('monotonicNs'), int) or not isinstance(ended.get('monotonicNs'), int):
        fail('build-result.json monotonic boundaries')
    check((ended['monotonicNs'] - started['monotonicNs']) / 1e9 == result['elapsedSeconds'], 'build-result.json elapsed time')
    cases = list(ET.fromstring(raw['junit.xml']).iter('testcase'))
    check(len(cases) == BUNDLE_CASE_COUNT and not any(list(case) for case in cases), 'junit.xml complete passing cases')
    for name in ('pr47-hosted-darwin-555b9a74.log', 'pr48-hosted-darwin-8e10a593.log'):
        log = raw[name].decode()
        check(f'collected {BUNDLE_CASE_COUNT} items' in log and 'builder failed with exit code 124' in log, name + ' whole-suite failure')
        check('test_generated_stages_reused_approved_compiled_fresh' in log, name + ' active stage-reuse case')
    print(f'Validated isolated {BUNDLE_CASE_COUNT}-case pass and both retained hosted failures; new hosted acceptance remains pending.')


if __name__ == '__main__':
    validate(Path(__file__).resolve().parent)
