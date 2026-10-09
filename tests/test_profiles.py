"""Version-only SQLite settings never introduce application catalogs or SQL operations."""

from collections.abc import Callable
from pathlib import Path

import pytest

from belay.sqlite.errors import SqlError
from belay.sqlite.profiles import DEFAULT_PROFILE, profile
from migration_check.lean_inputs import sql_inputs
from belay.sqlite.sql_tree import Tree
from belay.sqlite.translate import starting_schema, statements

pytestmark = pytest.mark.parser


@pytest.mark.integration
@pytest.mark.requires_native
def test_no_framework_directives_or_reserved_catalog_names(parse_sql: Callable[..., Tree]) -> None:
    """Comments stay comments, and application bookkeeping names are ordinary tables."""
    assert profile('3.51.0') == DEFAULT_PROFILE
    selected = profile('3.46.0')
    schema = starting_schema(parse_sql('CREATE TABLE _sqlx_migrations(x TEXT);'))
    plain = statements(parse_sql('ALTER TABLE _sqlx_migrations ADD y TEXT;'))
    commented = statements(parse_sql('-- no-transaction\nALTER TABLE _sqlx_migrations ADD y TEXT;'))
    assert sql_inputs(schema, plain, selected) == sql_inputs(schema, commented, selected)
    assert '.createTable' in sql_inputs((), statements(parse_sql('CREATE TABLE t(x TEXT);')), selected)


@pytest.mark.unit
def test_catalog_json_and_unknown_versions_reject(tmp_path: Path) -> None:
    """Neither existing manifest files nor application identities can select implicit behavior."""
    manifest = tmp_path / 'profile.json'
    manifest.write_text('{"kind":"sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1",'
                        '"migration":{"version":7,"description":"x"},"previous":[]}')
    for value in (str(manifest), manifest.read_text(), '', '3.46', ' 3.46.0'):
        with pytest.raises(SqlError) as rejected:
            profile(value)
        assert rejected.value.status == 'INPUT_ERROR', value
    with pytest.raises(SqlError) as rejected:
        profile('3.45.0')
    assert rejected.value.status == 'UNSUPPORTED'
