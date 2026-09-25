"""Exercise the unchanged real migration and reject semantic/input-baseline drift."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
# Identity of upstream 5b10eb09c664d316b7384210399b02e6127f4027's shell migration.
UPSTREAM_SQL_SHA256 = '3e998a7f7df2cdcc4593e3a8b0a4e3cc7da3f798869021e27638793ef17c589e'


def invoke(runtime: Path, pilot: Path, expected: str, label: str,
           artifacts: Path | None = None) -> dict[str, object]:
    """Use exactly the public inputs and protected closure, with bounded child execution."""
    command = [str(runtime / 'bin/migration-check'), 'verify', '--format', 'json',
               '--profile', str(pilot / 'profile.json'), '--schema', str(pilot / 'schema.sql'),
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
        assert hashlib.sha256(original_sql).hexdigest() == UPSTREAM_SQL_SHA256
        artifacts = work / 'artifacts'
        report = invoke(runtime, pilot, 'VERIFIED', 'unchanged migration and protected closure', artifacts)
        inputs = report['inputs']
        assert isinstance(inputs, dict)
        baseline = json.loads((pilot / 'approved/baseline.json').read_text())
        approved = {key: value for key, value in inputs.items() if key.startswith('approved/')}
        assert approved == baseline
        assert {'approved/AtuinSchema.lean', 'approved/AtuinCatalog.lean'} <= set(approved)
        for name in ('schema.sql', 'migration.sql', 'profile.json'):
            assert inputs[name] == hashlib.sha256((pilot / name).read_bytes()).hexdigest()
        assert '.sqlite346Sqlx' in (artifacts / 'SqlInputs.lean').read_text()
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

        profile = pilot / 'profile.json'
        original_profile = profile.read_bytes()
        data = json.loads(original_profile)
        checksum = data['previous'][0]['checksum']
        data['previous'][0]['checksum'] = ('0' if checksum[0] != '0' else '1') + checksum[1:]
        profile.write_text(json.dumps(data))
        invoke(runtime, pilot, 'UNVERIFIED', 'altered prior catalog checksum')
        profile.write_bytes(original_profile)

        next_meaning = pilot / 'NextInterpretation.lean'
        original_meaning = next_meaning.read_text()
        assert 'AtuinSchema.fields' in original_meaning
        next_meaning.write_text(original_meaning.replace('AtuinSchema.fields', '(AtuinSchema.fields.drop 1)'))
        invoke(runtime, pilot, 'UNVERIFIED', 'candidate omits old stored id')
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
    print('Atuin CLI: unchanged migration verified; schema, catalog, interpretation and proof drift rejected')


if __name__ == '__main__':
    if len(sys.argv) > 2:
        raise SystemExit('usage: atuin_cli_test.py [RUNTIME_ROOT]')
    main(Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT)
