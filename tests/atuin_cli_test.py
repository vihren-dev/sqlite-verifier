"""Exercise the explicit source-backed SQL example and reject protected-meaning drift."""

import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]


def invoke(runtime: Path, pilot: Path, expected: str, label: str,
           artifacts: Path | None = None) -> dict[str, object]:
    """Use exactly the public inputs and protected closure, with bounded child execution."""
    command = [str(runtime / 'bin/migration-check'), 'verify', '--format', 'json',
               '--profile', '3.46.0', '--schema', str(pilot / 'schema.sql'),
               '--migration', str(pilot / 'migration.sql'),
               '--requirements', str(pilot / 'approved/Requirements.lean'),
               '--interpretation', str(pilot / 'approved/Interpretation.lean'),
               '--next-interpretation', str(pilot / 'NextInterpretation.lean'),
               '--proofs', str(pilot / 'Proofs.lean'),
               '--approved-baseline', str(pilot / 'approved/baseline.json')]
    if artifacts is not None:
        command += ['--artifacts', str(artifacts)]
    print(f'Atuin CLI: {label}', flush=True)
    result = subprocess.run(command, cwd=pilot.parent, capture_output=True, text=True, timeout=180)
    report: dict[str, object] = json.loads(result.stdout)
    assert report['status'] == expected, (label, report, result.stderr)
    assert result.returncode == (0 if expected == 'VERIFIED' else 1), (label, result)
    if expected == 'UNVERIFIED':
        diagnostic = str(report.get('message', ''))
        assert 'error:' in diagnostic or 'unapproved axiom:' in diagnostic, (label, report)
        assert 'timed out' not in diagnostic.lower(), (label, report)
    return report


def replace_bytes(path: Path, original: bytes, old: bytes, new: bytes) -> None:
    """Ensure an adversarial source mutation actually changes the tested input."""
    changed = original.replace(old, new)
    assert changed != original, (path, old)
    path.write_bytes(changed)


def main(runtime: Path) -> None:
    """Run against a source build or an installed runtime containing the same reviewed bundle."""
    with TemporaryDirectory(prefix='atuin-cli-') as temporary:
        work = Path(temporary)
        pilot = work / 'pilot'
        shutil.copytree(runtime / 'examples/atuin', pilot)
        migration = pilot / 'migration.sql'
        original_sql = migration.read_bytes()
        assert b'alter table history add column shell text;' in original_sql
        artifacts = work / 'artifacts'
        report = invoke(runtime, pilot, 'VERIFIED', 'explicit SQL and protected closure', artifacts)
        assert report['statements'] == 5 and report['profile'] == '3.46.0'
        inputs = report['inputs']
        assert isinstance(inputs, dict)
        baseline = json.loads((pilot / 'approved/baseline.json').read_text())
        approved = {key: value for key, value in inputs.items() if key.startswith('approved/')}
        assert approved == {key: value for key, value in baseline.items() if key.startswith('approved/')}
        assert {'approved/SchemaBinding.lean', 'approved/HistoryModel.lean',
                'approved/HistoryDecoding.lean', 'approved/HistoryMapping.lean',
                'approved/AtuinCatalog.lean'} <= set(approved)
        assert inputs['schema.sql'] == baseline['schema.sql']
        assert 'candidate/HistoryDecodingChecks.lean' in inputs
        assert 'def startSchema' in (artifacts / 'SchemaInputs.lean').read_text()
        for name in ('schema.sql', 'migration.sql'):
            assert inputs[name] == hashlib.sha256((pilot / name).read_bytes()).hexdigest()
        assert 'def profile : ExecutionProfile := .sqlite346' in (artifacts / 'SqlInputs.lean').read_text()
        assert 'profile.json' not in inputs
        assert json.loads((artifacts / 'inputs.json').read_text()) == inputs

        replace_bytes(migration, original_sql, b'add column shell text;', b'add column other text;')
        invoke(runtime, pilot, 'UNVERIFIED', 'changed added column')
        migration.write_bytes(original_sql)

        schema = pilot / 'schema.sql'
        original_schema = schema.read_text()
        assert 'id text primary key' in original_schema
        replace_bytes(schema, original_schema.encode(), b'id text primary key', b'id text')
        invoke(runtime, pilot, 'INPUT_ERROR', 'omitted protected original primary key')
        schema.write_text(original_schema)

        checksum = re.search(rb"X'([0-9A-Fa-f]+)'", original_sql)
        assert checksum is not None
        offset = checksum.start(1)
        changed = b'0' if original_sql[offset:offset + 1] != b'0' else b'1'
        altered_checksum = original_sql[:offset] + changed + original_sql[offset + 1:]
        assert altered_checksum != original_sql
        migration.write_bytes(altered_checksum)
        invoke(runtime, pilot, 'UNVERIFIED', 'altered inserted bookkeeping identity')
        migration.write_bytes(original_sql)

        replace_bytes(migration, original_sql, b'add column shell text;',
                      b"add column shell text DEFAULT 'wrong';")
        invoke(runtime, pilot, 'UNSUPPORTED', 'incorrect non-NULL shell initialization')
        migration.write_bytes(original_sql)

        next_meaning = pilot / 'NextInterpretation.lean'
        original_meaning = next_meaning.read_text()
        reader = b'observe := HistoryMapping.observe true'
        for replacement, label in (
            (b'observe := fun database => (HistoryMapping.observe true database).map (List.drop 1)',
             'candidate drops a protected business history'),
            (b'observe := fun database => (HistoryMapping.observe true database).map '
             b'(fun histories => histories.map (fun history => { history with command := "" }))',
             'candidate erases protected command text'),
        ):
            replace_bytes(next_meaning, original_meaning.encode(), reader, replacement)
            invoke(runtime, pilot, 'UNVERIFIED', label)
            next_meaning.write_text(original_meaning)
        invariant_start = original_meaning.index('  invariant :=')
        invariant_end = original_meaning.index('  observe :=', invariant_start)
        weakened = (original_meaning[:invariant_start] + '  invariant _ := True\n' +
                    original_meaning[invariant_end:])
        assert weakened != original_meaning
        next_meaning.write_text(weakened)
        invoke(runtime, pilot, 'UNVERIFIED', 'candidate omits actual migration-history invariant')
        # This combined attack may reject at sealed script equality before the
        # approved actual-storage guard; it does not isolate the latter's proof.
        migration.write_bytes(altered_checksum)
        invoke(runtime, pilot, 'UNVERIFIED', 'wrong checksum hidden behind weakened representation')
        migration.write_bytes(original_sql)
        next_meaning.write_text(original_meaning)

        schema.write_text(original_schema + '\n-- changed schema approval bytes\n')
        invoke(runtime, pilot, 'INPUT_ERROR', 'protected starting schema bytes changed')
        schema.write_text(original_schema)
        for name in ('HistoryModel', 'HistoryDecoding'):
            protected = pilot / f'approved/{name}.lean'
            original = protected.read_bytes()
            protected.write_bytes(original + b'\n-- source-only approval drift\n')
            rejected = invoke(runtime, pilot, 'INPUT_ERROR', f'protected {name} changed')
            assert f'approved/{name}.lean' in str(rejected['message'])
            protected.write_bytes(original)

        catalog = pilot / 'approved/AtuinCatalog.lean'
        original_catalog = catalog.read_bytes()
        catalog.write_bytes(original_catalog + b'\n-- A new review is required even for source-only drift.\n')
        rejected = invoke(runtime, pilot, 'INPUT_ERROR', 'transitive approved dependency changed')
        assert 'approved/AtuinCatalog.lean' in str(rejected['message'])
        catalog.write_bytes(original_catalog)

        (pilot / 'Proofs.lean').write_text(
            'import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := by sorry\n')
        invoke(runtime, pilot, 'UNVERIFIED', 'unfinished proof')
    print('Atuin CLI: explicit SQL verified; schema, bookkeeping, initialization, interpretation and proof drift rejected')


if __name__ == '__main__':
    if len(sys.argv) > 2:
        raise SystemExit('usage: atuin_cli_test.py [RUNTIME_ROOT]')
    main(Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT)
