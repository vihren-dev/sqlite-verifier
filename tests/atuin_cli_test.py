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


def main(runtime: Path) -> None:
    """Run against a source build or an installed runtime containing the same reviewed bundle."""
    with TemporaryDirectory(prefix='atuin-cli-') as temporary:
        work = Path(temporary)
        pilot = work / 'pilot'
        shutil.copytree(runtime / 'examples/atuin', pilot)
        migration = pilot / 'migration.sql'
        original_sql = migration.read_bytes()
        assert b'ALTER TABLE history ADD COLUMN shell TEXT;' in original_sql
        artifacts = work / 'artifacts'
        report = invoke(runtime, pilot, 'VERIFIED', 'explicit SQL and protected closure', artifacts)
        assert report['statements'] == 5 and report['profile'] == '3.46.0'
        inputs = report['inputs']
        assert isinstance(inputs, dict)
        baseline = json.loads((pilot / 'approved/baseline.json').read_text())
        approved = {key: value for key, value in inputs.items() if key.startswith('approved/')}
        assert approved == baseline
        assert {'approved/AtuinSchema.lean', 'approved/AtuinCatalog.lean'} <= set(approved)
        for name in ('schema.sql', 'migration.sql'):
            assert inputs[name] == hashlib.sha256((pilot / name).read_bytes()).hexdigest()
        assert 'def profile : ExecutionProfile := .sqlite346' in (artifacts / 'SqlInputs.lean').read_text()
        assert 'profile.json' not in inputs
        assert json.loads((artifacts / 'inputs.json').read_text()) == inputs

        migration.write_bytes(original_sql.replace(b'shell', b'other'))
        invoke(runtime, pilot, 'UNVERIFIED', 'changed added column')
        migration.write_bytes(original_sql)

        schema = pilot / 'schema.sql'
        original_schema = schema.read_text()
        assert 'id text primary key' in original_schema
        schema.write_text(original_schema.replace('id text primary key', 'id text'))
        invoke(runtime, pilot, 'UNVERIFIED', 'omitted original primary key')
        schema.write_text(original_schema)

        checksum = re.search(rb"X'([0-9A-Fa-f]+)'", original_sql)
        assert checksum is not None
        offset = checksum.start(1)
        changed = b'0' if original_sql[offset:offset + 1] != b'0' else b'1'
        migration.write_bytes(original_sql[:offset] + changed + original_sql[offset + 1:])
        invoke(runtime, pilot, 'UNVERIFIED', 'altered inserted bookkeeping identity')
        migration.write_bytes(original_sql)

        migration.write_bytes(original_sql.replace(b'ADD COLUMN shell TEXT;', b"ADD COLUMN shell TEXT DEFAULT 'wrong';"))
        invoke(runtime, pilot, 'UNSUPPORTED', 'incorrect non-NULL shell initialization')
        migration.write_bytes(original_sql)

        next_meaning = pilot / 'NextInterpretation.lean'
        original_meaning = next_meaning.read_text()
        assert 'AtuinSchema.fields' in original_meaning
        next_meaning.write_text(original_meaning.replace('AtuinSchema.fields', '(AtuinSchema.fields.drop 1)'))
        invoke(runtime, pilot, 'UNVERIFIED', 'candidate omits old stored id')
        next_meaning.write_text(original_meaning)
        assert 'invariant := Conforms Generated.nextSchema' in original_meaning
        next_meaning.write_text(original_meaning.replace('invariant := Conforms Generated.nextSchema',
                                                       'invariant := fun _ => True'))
        invoke(runtime, pilot, 'UNVERIFIED', 'weakened resulting representation invariant')
        next_meaning.write_text(original_meaning)

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
