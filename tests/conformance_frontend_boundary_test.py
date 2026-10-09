"""The reusable SQL frontend runs with pinned parsers and no verification application."""

import ast
import json
from pathlib import Path
import shutil
import sys

import pytest

from belay.sqlite.parser_library import installed_library
from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / 'belay/sqlite'
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native('parser-library')]


def test_namespace_and_independent_imports() -> None:
    """The namespace contains one portion and no frontend source depends on application code."""
    assert not (ROOT / 'belay/__init__.py').exists()
    assert {path.name for path in (ROOT / 'belay').iterdir()} == {'sqlite'}
    for path in FRONTEND.glob('*.py'):
        for node in ast.walk(ast.parse(path.read_text())):
            if isinstance(node, ast.ImportFrom):
                assert not (node.module or '').startswith('migration_check'), path
            elif isinstance(node, ast.Import):
                assert not any(alias.name.startswith('migration_check') for alias in node.names), path
    assert not list((ROOT / 'migration_check').glob('sql_*.py'))


def test_only_frontend_copy_uses_real_parser(runtime_root: Path, tmp_path: Path) -> None:
    """An unrelated Python process preserves records, ordering and refusal spans without the application."""
    shutil.copytree(ROOT / 'belay', tmp_path / 'belay', ignore=shutil.ignore_patterns('__pycache__'))
    source = '''import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from belay.sqlite.admission import admit
from belay.sqlite.errors import SqlError
from belay.sqlite.profiles import profile
from belay.sqlite.dialects import ProfileIdentity
from belay.sqlite.parser_library import load
from belay.sqlite.sql_tree import SqlParser, parse
from belay.sqlite.structural import generated_inputs_wire, schema_wire
from belay.sqlite.translate import starting_schema, statements
selected = profile('3.51.0')
parser = SqlParser.for_profile(load(Path(sys.argv[2])), ProfileIdentity(selected.engine, selected.source_id))
schema = starting_schema(parse(parser, b'CREATE TABLE t(k BIGINT PRIMARY KEY NOT NULL,x TEXT);'
    b'CREATE INDEX second ON t(x); CREATE INDEX first ON t(k);', 'schema.sql'))
script = statements(parse(parser, "UPDATE t SET x='é' WHERE k=1;".encode(), 'update.sql'))
admit(schema, script)
record = generated_inputs_wire(schema, script, selected)
assert record['profile'] == 'sqlite351'
assert record['script'][0]['update']['value'] == {'text': {'bytes': [195, 169]}}
assert [index['name'] for index in record['schema'][0]['properties']['indexes']] == ['second', 'first']
assert [index['name'] for index in schema_wire(schema[0])['properties']['indexes']] == ['first', 'second']
try:
    bad = statements(parse(parser, b'UPDATE t SET x=upper(x) WHERE k=1;', 'bad.sql'))
    admit(schema, bad)
except SqlError as error:
    assert error.status == 'UNSUPPORTED'
    assert error.source == 'bad.sql' and error.end > error.start
else:
    raise AssertionError('unsupported expression was admitted')
assert not any(name.startswith('migration_check') for name in sys.modules)
print(json.dumps(record))
'''
    result = run_command([sys.executable, '-I', '-c', source, str(tmp_path),
                          str(installed_library(runtime_root.resolve(), sys.platform))],
                         cwd=tmp_path, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    assert json.loads(result.stdout)['version'] == 1
