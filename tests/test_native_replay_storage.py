"""Full native replay must bind actual file fixtures to the selected storage and reject bad conditions."""

import gzip
import hashlib
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from conformance.native_record import record_sql
from tests.runtime_support import CommandResult, run_command
from tools.check_resources import MIN_FREE_BYTES, check_resources
from conformance.case_format import Json
from conformance.corpus import load
import conformance.freeze_corpus as finalizer
import conformance.native_replay_report as execution
from tests.conformance_freeze_test import capture

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native('sqlite3')]


@pytest.fixture
def frozen(tmp_path: Path) -> Path:
    """One real frozen observation exercises the full command without replaying the large corpus."""
    record = record_sql('CREATE TABLE t(id INTEGER);', 'INSERT INTO t VALUES(2);',
                        name='storage-fixture', outputs=True)
    payload = json.dumps(record).encode() + b'\n'
    corpus = tmp_path / 'corpus'
    corpus.mkdir()
    (corpus / 'cases.jsonl.gz').write_bytes(gzip.compress(payload, mtime=0))
    (corpus / 'manifest.json').write_text(json.dumps({'corpusVersion': 1, 'recordedCases': 1,
        'casesSha256': hashlib.sha256(payload).hexdigest()}))
    return corpus


def invoke(corpus: Path, runtime: Path, output: Path, *arguments: str) -> CommandResult:
    """Use the real full-replay CLI, the selected pinned runtime and a short command bound."""
    return run_command([sys.executable, '-m', 'conformance.corpus', str(corpus),
                        '--runtime-root', str(runtime), '--native-check', '--output', str(output), *arguments],
                       cwd=ROOT, timeout=20, environment={**os.environ, 'PYTEST_DISABLE_PLUGIN_AUTOLOAD': '1'})


def test_explicit_storage_preserves_records_and_cleans_actual_files(tmp_path: Path) -> None:
    """Changing the selected directory preserves every native field while keeping ordinary files there."""
    roots = [tmp_path / 'first', tmp_path / 'second']
    fresh: list[dict[str, Json]] = []
    for root in roots:
        root.mkdir()
        paths: list[Path] = []
        fresh.append(record_sql('CREATE TABLE t(id INTEGER);', 'INSERT INTO t VALUES(?);',
            name='typed-file', outputs=True, parameters=[((1, 2),)], temporary_root=root, fixture_paths=paths))
        assert len(paths) == 1 and paths[0].parent.parent == root and paths[0].name == 'case.db'
        assert not paths[0].parent.exists() and list(root.iterdir()) == []
    assert fresh[0] == fresh[1]


def test_full_cli_retains_storage_and_unchanged_bindings(frozen: Path, runtime_root: Path, tmp_path: Path) -> None:
    """A successful full native check reports exact fixture paths and unchanged execution inputs."""
    storage = tmp_path / 'selected files'
    storage.mkdir()
    output = tmp_path / 'report.json'
    result = invoke(frozen, runtime_root, output, '--temporary-root', str(storage))
    assert result.returncode == 0, result.diagnostic()
    report = json.loads(output.read_text())
    native = report['nativeReplay']
    assert report['denominator'] == 1 and native['passed'] and native['bindingsUnchanged']
    assert native['bindingsBefore'] == native['bindingsAfter']
    audit = native['temporaryStorage']
    assert audit['selectedRoot'] == str(storage) and audit['databaseKind'] == 'ordinary-file'
    assert audit['allFixturesBeneathSelectedRoot'] and audit['fixtureCount'] == 1
    assert all(Path(path).parent.parent == storage and not Path(path).exists() for path in audit['fixturePaths'])
    assert audit['resourcesBefore']['freeBytes'] >= MIN_FREE_BYTES
    assert native['command'][1:3] == ['-m', 'conformance.corpus']
    assert list(storage.iterdir()) == []


@pytest.mark.parametrize('condition', ['unspecified', 'missing', 'file'])
def test_full_cli_refuses_unspecified_or_invalid_storage(
        frozen: Path, runtime_root: Path, tmp_path: Path, condition: str) -> None:
    """Missing selection and unusable explicit paths fail clearly rather than choosing ambient storage."""
    path = tmp_path / 'storage'
    if condition == 'file':
        path.write_text('not a directory')
    arguments = () if condition == 'unspecified' else ('--temporary-root', str(path))
    output = tmp_path / 'report.json'
    result = invoke(frozen, runtime_root, output, *arguments)
    assert result.returncode == 2 and not output.exists(), result.diagnostic()
    diagnostic = '--native-check requires --temporary-root' if condition == 'unspecified' else 'Temporary storage directory is missing or invalid'
    assert diagnostic in result.stderr, result.diagnostic()


def test_explicit_storage_refuses_insufficient_space_and_write_failure(tmp_path: Path) -> None:
    """Capacity and write failures identify the selected storage before native fixture creation."""
    with patch('tools.check_resources.shutil.disk_usage', return_value=SimpleNamespace(free=MIN_FREE_BYTES - 1)):
        with pytest.raises(ValueError, match='At least 10 GiB free'):
            check_resources(ROOT, temporary_root=tmp_path)
    with patch('tools.check_resources.tempfile.TemporaryDirectory', side_effect=PermissionError('read-only')):
        with pytest.raises(ValueError, match='Temporary storage directory is not writable'):
            check_resources(ROOT, temporary_root=tmp_path)


def test_freezer_retains_a_separate_operational_receipt(
        capture: tuple[Path, Path, dict[str, Json], dict[str, Json]], tmp_path: Path) -> None:
    """Explicit freezer storage is audited beside the new corpus without changing its native format."""
    directory, upstream, _capture, _record = capture
    output, receipt, storage = tmp_path / 'frozen', tmp_path / 'native-replay.json', tmp_path / 'storage'
    storage.mkdir()
    manifest = finalizer.freeze(directory, output, upstream=upstream,
                               temporary_root=storage, storage_report=receipt)
    native = json.loads(receipt.read_text())['nativeReplay']
    assert native['passed'] and native['bindingsUnchanged'] and native['temporaryStorage']['fixtureCount'] == 5
    assert native['temporaryStorage']['selectedRoot'] == str(storage)
    assert native['bindingsBefore']['runtimeSha256'] == {}
    loaded, records = load(output)
    assert loaded == manifest and len(records) == 5 and all(record['nativeVersion'] == 4 for record in records)
    assert 'nativeReplay' not in manifest and not receipt.is_relative_to(output)
    with pytest.raises(ValueError, match='receipt requires explicit storage'):
        finalizer.freeze(directory, tmp_path / 'other', upstream=upstream, storage_report=receipt)


def test_full_cli_cannot_write_the_report_inside_frozen_inputs(
        frozen: Path, runtime_root: Path, tmp_path: Path) -> None:
    """A replay report cannot alter the input bytes after its unchanged-binding check."""
    result = invoke(frozen, runtime_root, frozen / 'report.json', '--temporary-root', str(tmp_path))
    assert result.returncode == 2 and 'Replay report must be outside' in result.stderr, result.diagnostic()
    assert not (frozen / 'report.json').exists()


def test_full_cli_requires_native_check_for_a_storage_argument(frozen: Path, tmp_path: Path) -> None:
    """The CLI rejects a storage input that would be ignored by model-only classification."""
    result = run_command([sys.executable, '-m', 'conformance.corpus', str(frozen),
        '--temporary-root', str(tmp_path), '--output', str(tmp_path / 'report.json')], cwd=ROOT, timeout=5)
    assert result.returncode == 2 and '--temporary-root requires --native-check' in result.stderr, result.diagnostic()


def test_native_report_refuses_changed_input_bytes(
        frozen: Path, runtime_root: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A change during acquisition must fail the audit even if native comparison reports no failure."""
    _manifest, records = load(frozen)
    def change_input(selected: list[dict[str, Json]], *, temporary_root: Path, fixture_paths: list[Path]) -> None:
        """Alter an actual input file to expose the unchanged-binding requirement."""
        with (frozen / 'manifest.json').open('a') as source:
            source.write('\n')
    monkeypatch.setattr(execution, 'native_replay', change_input)
    with pytest.raises(ValueError, match='Full native replay inputs changed'):
        execution.report(frozen, records, runtime_root, tmp_path)


@pytest.mark.parametrize('storage_condition', ['unspecified', 'missing', 'valid'])
def test_freezer_cli_requires_storage_and_names_its_separate_receipt(
        capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
        tmp_path: Path, storage_condition: str) -> None:
    """The real freezer CLI refuses bad selection and publishes its native audit beside the output."""
    directory, upstream, _capture, _record = capture
    storage, output = tmp_path / 'storage', tmp_path / 'published'
    if storage_condition == 'valid':
        storage.mkdir()
    arguments = [] if storage_condition == 'unspecified' else ['--temporary-root', str(storage)]
    result = run_command([sys.executable, '-m', 'conformance.freeze_corpus', '--input', str(directory),
        '--upstream', str(upstream), '--output', str(output), *arguments], cwd=ROOT, timeout=30)
    receipt = output.with_name(output.name + '-native-replay.json')
    if storage_condition != 'valid':
        diagnostic = '--temporary-root' if storage_condition == 'unspecified' else 'Temporary storage directory is missing or invalid'
        assert result.returncode == 2 and diagnostic in result.stderr, result.diagnostic()
        assert not output.exists() and not receipt.exists()
    else:
        assert result.returncode == 0, result.diagnostic()
        _manifest, records = load(output)
        native = json.loads(receipt.read_text())['nativeReplay']
        assert native['passed'] and native['temporaryStorage']['fixtureCount'] == len(records)
        assert native['temporaryStorage']['selectedRoot'] == str(storage)
