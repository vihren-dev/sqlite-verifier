"""Exercise the explicit source-backed SQL example and reject protected-meaning drift."""

import hashlib
import json
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

        replace_bytes(migration, original_sql, b'add column shell text;', b'add column other text;')
        invoke(runtime, pilot, 'UNVERIFIED', 'changed SQL with stale candidate proof')
        facts = pilot / 'AtuinFacts.lean'
        original_facts = facts.read_bytes()
        replace_bytes(facts, original_facts, b'name := "shell"', b'name := "other"')
        alternative = invoke(runtime, pilot, 'VERIFIED', 'different new field, same old business contract')
        alternative_inputs = alternative['inputs']
        assert isinstance(alternative_inputs, dict)
        assert {key: value for key, value in alternative_inputs.items()
                if key.startswith('approved/')} == approved
        facts.write_bytes(original_facts)
        migration.write_bytes(original_sql)

        schema = pilot / 'schema.sql'
        original_schema = schema.read_text()
        assert 'id text primary key' in original_schema
        replace_bytes(schema, original_schema.encode(), b'id text primary key', b'id text')
        invoke(runtime, pilot, 'INPUT_ERROR', 'omitted protected original primary key')
        schema.write_text(original_schema)

        replace_bytes(migration, original_sql, b'add column shell text;',
                      b"add column shell text DEFAULT 'new';")
        invoke(runtime, pilot, 'UNSUPPORTED', 'default semantics remain outside the supported subset')
        migration.write_bytes(original_sql)

        next_meaning = pilot / 'NextInterpretation.lean'
        original_meaning = next_meaning.read_text()
        reader = b'observe := HistoryMapping.observe'
        for replacement, label in (
            (b'observe := fun database => (HistoryMapping.observe database).map (List.drop 1)',
             'candidate drops a protected business history'),
            (b'observe := fun database => (HistoryMapping.observe database).map '
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
        invoke(runtime, pilot, 'UNVERIFIED', 'candidate omits schema and decoding invariant')
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

        mapping = pilot / 'approved/HistoryMapping.lean'
        original_mapping = mapping.read_bytes()
        mapping.write_bytes(original_mapping + b'\n-- Protected interpretation dependency changed.\n')
        rejected = invoke(runtime, pilot, 'INPUT_ERROR', 'transitive approved dependency changed')
        assert 'approved/HistoryMapping.lean' in str(rejected['message'])
        mapping.write_bytes(original_mapping)

        (pilot / 'Proofs.lean').write_text(
            'import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := by sorry\n')
        invoke(runtime, pilot, 'UNVERIFIED', 'unfinished proof')
    print('Atuin CLI: two migrations preserve the same old business contract; stale proofs and protected-meaning drift rejected')


if __name__ == '__main__':
    if len(sys.argv) > 2:
        raise SystemExit('usage: atuin_cli_test.py [RUNTIME_ROOT]')
    main(Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT)
