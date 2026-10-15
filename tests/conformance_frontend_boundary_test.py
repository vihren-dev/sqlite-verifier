"""The reusable SQL frontend runs with pinned parsers and no verification application."""

import json
from pathlib import Path
import shutil
import sys

import pytest

from belay.sqlite.parser_library import installed_library
from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native('parser-library')]


def test_only_frontend_copy_uses_real_parser(runtime_root: Path, tmp_path: Path) -> None:
    """An unrelated Python process maps statements, keeps their order and refuses with spans, without the application."""
    shutil.copytree(ROOT / 'belay', tmp_path / 'belay', ignore=shutil.ignore_patterns('__pycache__'))
    source = '''import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from belay.sqlite.errors import SqlError
from belay.sqlite.profiles import profile
from belay.sqlite.dialects import ProfileIdentity
from belay.sqlite.parser_library import load
from belay.sqlite.sql_tree import SqlParser, parse
from belay.sqlite.syntax import script_record, statements
selected = profile('3.51.0')
parser = SqlParser.for_profile(load(Path(sys.argv[2])), ProfileIdentity(selected.engine, selected.source_id))
schema = statements(parse(parser, b'CREATE TABLE t(k BIGINT PRIMARY KEY NOT NULL,x TEXT);'
    b'CREATE INDEX second ON t(x); CREATE INDEX first ON t(k);', 'schema.sql'))
script = statements(parse(parser, "UPDATE t SET x='é' WHERE k=1;".encode(), 'update.sql'))
record = script_record(selected, schema, script)
assert record['release'] == '3.51.0' and record['sourceId'] == selected.source_id
assert record['script'][0]['update']['assignments'] == [['x', {'string': {'bytes': [195, 169]}}]]
assert [item['createIndex']['name'] for item in record['schema'][1:]] == ['second', 'first']
try:
    statements(parse(parser, b'UPDATE t SET x=x || 1 WHERE k=1;', 'bad.sql'))
except SqlError as error:
    assert error.status == 'UNSUPPORTED'
    assert error.source == 'bad.sql' and error.end > error.start
else:
    raise AssertionError('unsupported expression was mapped')
assert not any(name.startswith('migration_check') for name in sys.modules)
print(json.dumps(record))
'''
    result = run_command([sys.executable, '-I', '-c', source, str(tmp_path),
                          str(installed_library(runtime_root.resolve(), sys.platform))],
                         cwd=tmp_path, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    assert json.loads(result.stdout)['version'] == 3
