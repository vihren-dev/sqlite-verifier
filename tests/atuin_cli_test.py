"""Exercise each Atuin preservation scenario through the selected public runtime."""

from __future__ import annotations

from collections.abc import Callable
import hashlib
import json
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.atuin, pytest.mark.requires_lean,
              pytest.mark.requires_native]


@pytest.fixture
def pilot(example_factory: Callable[[str], Path]) -> Path:
    """Give every scenario its own complete approved/candidate source tree."""
    return example_factory('atuin')


@pytest.fixture
def verify(runtime_root: Path, pilot: Path,
           command_runner: Callable[..., CommandResult]) -> Callable[..., dict[str, object]]:
    """Keep public status, process exit and non-timeout proof rejection assertions together."""
    def invoke(expected: str, artifacts: Path | None = None) -> dict[str, object]:
        """Verify this case's exact files under the same protected closure and deadline."""
        command = [str(runtime_root / 'bin/migration-check'), 'verify', '--format', 'json',
                   '--profile', '3.46.0', '--schema', str(pilot / 'schema.sql'),
                   '--migration', str(pilot / 'migration.sql'),
                   '--requirements', str(pilot / 'approved/Requirements.lean'),
                   '--interpretation', str(pilot / 'approved/Interpretation.lean'),
                   '--next-interpretation', str(pilot / 'NextInterpretation.lean'),
                   '--proofs', str(pilot / 'Proofs.lean'),
                   '--approved-baseline', str(pilot / 'approved/baseline.json')]
        if artifacts is not None:
            command += ['--artifacts', str(artifacts)]
        result = command_runner(command, cwd=pilot.parent, timeout=180)
        report = result.json_object()
        assert report['status'] == expected, (report, result)
        assert result.returncode == (0 if expected == 'VERIFIED' else 1), result
        if expected == 'UNVERIFIED':
            diagnostic = str(report.get('message', ''))
            assert 'error:' in diagnostic or 'unapproved axiom:' in diagnostic, (report, result)
            assert 'timed out' not in diagnostic.lower(), (report, result)
        return report
    return invoke


def replace_bytes(path: Path, old: bytes, new: bytes) -> None:
    """Require each deliberate source mutation to change the copied input."""
    original = path.read_bytes()
    changed = original.replace(old, new)
    assert changed != original, (path, old)
    path.write_bytes(changed)


@pytest.mark.approval
@pytest.mark.kernel
def test_valid_migration_preserves_history(pilot: Path, verify: Callable[..., dict[str, object]],
                                          tmp_path: Path) -> None:
    """Accept the payload with exact protected hashes and complete generated artifacts."""
    assert b'alter table history add column shell text;' in (pilot / 'migration.sql').read_bytes()
    artifacts = tmp_path / 'artifacts'
    report = verify('VERIFIED', artifacts)
    assert report['statements'] == 1 and report['profile'] == '3.46.0'
    inputs = report['inputs']
    assert isinstance(inputs, dict)
    baseline = json.loads((pilot / 'approved/baseline.json').read_text())
    approved = {key: value for key, value in inputs.items() if key.startswith('approved/')}
    assert approved == {key: value for key, value in baseline.items() if key.startswith('approved/')}
    assert {'approved/SchemaBinding.lean', 'approved/HistoryModel.lean',
            'approved/HistoryDecoding.lean', 'approved/HistoryMapping.lean'} <= set(approved)
    assert inputs['schema.sql'] == baseline['schema.sql']
    assert 'candidate/HistoryDecodingChecks.lean' in inputs
    assert 'def startSchema' in (artifacts / 'SchemaInputs.lean').read_text()
    for name in ('schema.sql', 'migration.sql'):
        assert inputs[name] == hashlib.sha256((pilot / name).read_bytes()).hexdigest()
    assert 'def profile : ExecutionProfile := .sqlite346' in (artifacts / 'SqlInputs.lean').read_text()
    assert 'profile.json' not in inputs
    assert json.loads((artifacts / 'inputs.json').read_text()) == inputs


@pytest.mark.kernel
def test_changed_sql_rejects_stale_proof(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Reject a changed added column when the candidate's proof facts remain stale."""
    replace_bytes(pilot / 'migration.sql', b'add column shell text;', b'add column other text;')
    verify('UNVERIFIED')


@pytest.mark.approval
@pytest.mark.kernel
def test_different_field_preserves_contract(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Accept another nullable field using unchanged approved files and updated candidate facts."""
    replace_bytes(pilot / 'migration.sql', b'add column shell text;', b'add column other text;')
    replace_bytes(pilot / 'AtuinFacts.lean', b'name := "shell"', b'name := "other"')
    report = verify('VERIFIED')
    inputs = report['inputs']
    assert isinstance(inputs, dict)
    baseline = json.loads((pilot / 'approved/baseline.json').read_text())
    assert {key: value for key, value in inputs.items() if key.startswith('approved/')} == {
        key: value for key, value in baseline.items() if key.startswith('approved/')}


@pytest.mark.approval
def test_omitted_original_primary_key(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Reject removal of the protected original primary key before checking a proof."""
    replace_bytes(pilot / 'schema.sql', b'id text primary key', b'id text')
    verify('INPUT_ERROR')


def test_unsupported_default(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Report unsupported default semantics instead of accepting an unmodeled initialization."""
    replace_bytes(pilot / 'migration.sql', b'add column shell text;', b"add column shell text DEFAULT 'new';")
    verify('UNSUPPORTED')


@pytest.mark.approval
@pytest.mark.kernel
def test_drops_history(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Reject a candidate reader that omits the first protected business history."""
    replace_bytes(pilot / 'NextInterpretation.lean', b'observe := HistoryMapping.observe',
                  b'observe := fun database => (HistoryMapping.observe database).map (List.drop 1)')
    verify('UNVERIFIED')


@pytest.mark.approval
@pytest.mark.kernel
def test_erases_commands(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Reject a candidate reader that replaces protected command text with empty strings."""
    replace_bytes(pilot / 'NextInterpretation.lean', b'observe := HistoryMapping.observe',
                  b'observe := fun database => (HistoryMapping.observe database).map '
                  b'(fun histories => histories.map (fun history => { history with command := "" }))')
    verify('UNVERIFIED')


@pytest.mark.approval
@pytest.mark.kernel
def test_weakened_invariant(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Reject removal of the resulting schema and complete-decoding invariant."""
    path = pilot / 'NextInterpretation.lean'
    original = path.read_text()
    start = original.index('  invariant :=')
    end = original.index('  observe :=', start)
    weakened = original[:start] + '  invariant _ := True\n' + original[end:]
    assert weakened != original
    path.write_text(weakened)
    verify('UNVERIFIED')


@pytest.mark.approval
def test_schema_approval_bytes_changed(pilot: Path, verify: Callable[..., dict[str, object]]) -> None:
    """Reject even a comment-only change to approved starting-schema bytes."""
    path = pilot / 'schema.sql'
    path.write_bytes(path.read_bytes() + b'\n-- changed schema approval bytes\n')
    verify('INPUT_ERROR')


@pytest.mark.approval
@pytest.mark.parametrize('name', ['HistoryModel', 'HistoryDecoding', 'HistoryMapping'])
def test_approved_source_changed(pilot: Path, verify: Callable[..., dict[str, object]], name: str) -> None:
    """Name the changed protected model, decoder or transitive mapping when source approval drifts."""
    path = pilot / f'approved/{name}.lean'
    path.write_bytes(path.read_bytes() + b'\n-- source-only approval drift\n')
    report = verify('INPUT_ERROR')
    assert f'approved/{name}.lean' in str(report['message'])
