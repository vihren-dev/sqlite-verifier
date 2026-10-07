"""Validate the retained isolated build and hosted failures without executing their helpers."""

import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias
import xml.etree.ElementTree as ET

Json: TypeAlias = None | bool | int | float | str | list['Json'] | dict[str, 'Json']
RAW_MANIFEST_SHA256 = '1c1408859f1d7299d101899b7ac3b669e25a30cae18a0f81da7a51f2de23445f'
"""Bind all sixteen original observations, including the earlier whole-suite failures."""
BUNDLE_TEST_FILES = ('tests/bundle_test.py', 'tests/proof_exporter_test.py',
                     'tests/stage_reuse_test.py', 'tests/generated_inputs_test.py')
"""The isolated build retains the exact four-file bundle gate from the failed derivation."""


def digest(payload: bytes) -> str:
    """Compare original bytes independently of compressed transport."""
    return hashlib.sha256(payload).hexdigest()


def document(payload: bytes) -> dict[str, Json]:
    """Require object-shaped observations before checking their recorded fields."""
    value = json.loads(payload)
    assert isinstance(value, dict)
    return value


def validate(root: Path) -> None:
    """Require exact retained evidence, complete passing cases and unchanged identities."""
    manifest_bytes = (root / 'raw-sha256.json').read_bytes()
    assert digest(manifest_bytes) == RAW_MANIFEST_SHA256
    manifest = document(manifest_bytes)
    assert len(manifest) == 16
    raw: dict[str, bytes] = {}
    for name, entry in manifest.items():
        assert isinstance(entry, dict) and isinstance(entry['gzip'], str)
        compressed = (root / entry['gzip']).read_bytes()
        assert digest(compressed) == entry['gzipSha256']
        payload = gzip.decompress(compressed)
        assert len(payload) == entry['bytes'] and digest(payload) == entry['sha256']
        raw[name] = payload
    original = document(raw['raw-sha256.json'])
    assert len(original) == 12
    for name, entry in original.items():
        assert isinstance(entry, dict)
        assert len(raw[name]) == entry['bytes'] and digest(raw[name]) == entry['sha256']
    before, after = (document(raw[name]) for name in ('identity-before.json', 'identity-after.json'))
    assert before == after
    for role, name in (('observer', 'observe.py'), ('metadataHelper', 't04c_metadata.py'),
                       ('derivation', 'exact-derivation.drv')):
        binding = before[role]
        assert isinstance(binding, dict) and digest(raw[name]) == binding['sha256']
    preflight, result = (document(raw[name]) for name in ('preflight.json', 'build-result.json'))
    declaration = preflight['declaration']
    assert isinstance(declaration, dict) and isinstance(declaration['installPhase'], str)
    command = declaration['installPhase']
    assert 'timeout 420 python3 -m pytest ' + ' '.join(BUNDLE_TEST_FILES) in command
    assert 'PYTEST_DISABLE_PLUGIN_AUTOLOAD=1' in command and '-p no:cacheprovider' in command
    assert preflight['previousValidityExit'] == 1 and preflight['outputExisted'] is False
    assert result['returncode'] == 0 and result['timedOut'] is False
    started, ended = result['started'], result['ended']
    assert isinstance(started, dict) and isinstance(ended, dict)
    assert isinstance(started['monotonicNs'], int) and isinstance(ended['monotonicNs'], int)
    assert (ended['monotonicNs'] - started['monotonicNs']) / 1e9 == result['elapsedSeconds']
    cases = list(ET.fromstring(raw['junit.xml']).iter('testcase'))
    assert len(cases) == 42
    assert not any(list(case) for case in cases)
    for name in ('pr47-hosted-darwin-555b9a74.log', 'pr48-hosted-darwin-8e10a593.log'):
        log = raw[name].decode()
        assert 'collected 42 items' in log and 'builder failed with exit code 124' in log
        assert 'test_generated_stages_reused_approved_compiled_fresh' in log
    print('Validated isolated 42-case pass and both retained hosted failures; new hosted acceptance remains pending.')


if __name__ == '__main__':
    validate(Path(__file__).resolve().parent)
