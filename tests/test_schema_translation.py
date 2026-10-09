"""Real-parser regression coverage for rich declarative baselines and narrow migrations."""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from belay.sqlite.sql_model import transition
from migration_check.lean_inputs import sql_inputs
from belay.sqlite.sql_tree import Tree
from belay.sqlite.translate import starting_schema, statements
from tests.sql_fixtures import RICH_BASELINE

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]
UNSUPPORTED_METADATA = [
    'CREATE TABLE t(x INTEGER PRIMARY KEY);', 'CREATE TABLE t(x TEXT PRIMARY KEY DESC);',
    'CREATE TABLE t(x TEXT PRIMARY KEY ON CONFLICT REPLACE);',
    'CREATE TABLE t(x BIGINT PRIMARY KEY AUTOINCREMENT);',
    'CREATE TABLE t(x TEXT NOT NULL ON CONFLICT IGNORE);',
    'CREATE TABLE t(x TEXT DEFAULT CURRENT_DATE);', 'CREATE TABLE t(x TEXT DEFAULT CURRENT_TIME);',
    'CREATE TABLE t(x TEXT DEFAULT (CURRENT_TIMESTAMP));', 'CREATE TABLE t(x TEXT DEFAULT NULL);',
    'CREATE TABLE t(x TEXT DEFAULT 0);', 'CREATE TABLE t(x TEXT CHECK(x));',
    'CREATE TABLE t(x TEXT REFERENCES u);', 'CREATE TABLE t(x TEXT COLLATE NOCASE);',
    'CREATE TABLE t(x TEXT, CONSTRAINT named UNIQUE(x));', 'CREATE TABLE t(x TEXT, PRIMARY KEY(x));',
    'CREATE TABLE t(x TEXT, UNIQUE(x DESC));', 'CREATE TABLE t(x TEXT, UNIQUE(x) ON CONFLICT IGNORE);',
    'CREATE TABLE t(x TEXT) WITHOUT ROWID;', 'CREATE TABLE t(x TEXT) STRICT;',
    'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(lower(x));',
    'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x) WHERE x IS NOT NULL;',
    'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x COLLATE NOCASE);',
    'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x DESC);',
    'CREATE TABLE t(x TEXT); CREATE TRIGGER tr AFTER INSERT ON t BEGIN SELECT 1; END;',
]


def test_metadata_and_indexes_survive_nullable_add(parse_sql: Callable[..., Tree]) -> None:
    """Metadata and ordered key projections remain unchanged while ADD appends NULL storage."""
    schema = starting_schema(parse_sql(RICH_BASELINE))
    events, ledger = schema
    assert events.primary_key == ("id",)
    assert not events.columns[0].not_null
    assert events.unique_keys == (("occurred", "message"),)
    assert [index.name for index in events.indexes] == ["event_time", "author_message"]
    assert events.indexes[1].unique
    assert ledger.columns[0].declared_type == "bigInt"
    assert ledger.columns[2].affinity == "numeric"
    assert ledger.columns[2].current_timestamp and ledger.columns[2].not_null
    assert ledger.columns[3].declared_type == "boolean"
    script = statements(parse_sql('ALTER TABLE events ADD extra TEXT;'))
    after, failure = transition(schema, script)
    assert not failure
    assert after[0].indexes == events.indexes
    assert after[0].primary_key == events.primary_key
    assert after[0].unique_keys == events.unique_keys
    assert after[0].columns[:-1] == events.columns
    assert after[1] == ledger
    generated = sql_inputs(schema, script)
    for binding in ('declaredType := .bigInt', 'notNull := true',
                    'defaultValue := some .currentTimestamp', 'primaryKey := ["id"]',
                    'name := "author_message"', 'unique := true'):
        assert binding in generated
    changed = starting_schema(parse_sql(RICH_BASELINE.replace('UNIQUE(occurred, message)', 'UNIQUE(message, occurred)')))
    assert sql_inputs(changed, script) != generated
    with pytest.raises(SqlError):
        sql_inputs(schema, statements(parse_sql('CREATE TABLE unrelated(x TEXT);')))


def test_create_cannot_collide_with_preserved_index(parse_sql: Callable[..., Tree]) -> None:
    """The model's table-only CREATE primitive cannot bypass SQLite's shared namespace."""
    schema = starting_schema(parse_sql('CREATE TABLE t(a TEXT); CREATE INDEX other ON t(a);'))
    with pytest.raises(SqlError) as rejected:
        sql_inputs(schema, statements(parse_sql('CREATE TABLE other(x TEXT);')))
    assert rejected.value.status == 'UNSUPPORTED'


@pytest.mark.parametrize("sql", UNSUPPORTED_METADATA)
def test_unsupported_metadata_cannot_disappear(parse_sql: Callable[..., Tree], sql: str) -> None:
    """Every optional clause outside the fixed structural subset must reject."""
    with pytest.raises(SqlError) as rejected:
        starting_schema(parse_sql(sql))
    assert rejected.value.status == 'UNSUPPORTED'


def test_statistics_are_exact_engine_managed_baseline_objects(parse_sql: Callable[..., Tree]) -> None:
    """No arbitrary reserved table or modified optimizer metadata enters the baseline."""
    schema = starting_schema(parse_sql('CREATE TABLE sqlite_stat1(tbl,idx,stat);'
                                       'CREATE TABLE sqlite_stat4(tbl,idx,neq,nlt,ndlt,sample);'))
    assert [table.name for table in schema] == ['sqlite_stat1', 'sqlite_stat4']
    assert all(column.declared_type == 'untyped' and column.affinity == 'blob'
               for table in schema for column in table.columns)
    assert starting_schema(parse_sql('CREATE TABLE ordinary(x);'))[0].columns[0].declared_type == 'untyped'
    for sql in ('CREATE TABLE sqlite_unknown(x);', 'CREATE TABLE sqlite_stat1(tbl,idx,stat TEXT);',
                'CREATE TABLE sqlite_stat1(tbl,idx,stat,extra);',
                'CREATE TABLE sqlite_stat1(tbl,idx,stat NOT NULL);',
                'CREATE TABLE sqlite_stat4(tbl,idx,neq,nlt,sample,ndlt);'):
        with pytest.raises(SqlError):
            starting_schema(parse_sql(sql))
    for sql in ('ALTER TABLE sqlite_stat1 ADD extra TEXT;', 'ALTER TABLE ordinary ADD extra;'):
        with pytest.raises(SqlError):
            statements(parse_sql(sql))


def test_global_namespace_references_and_aliases(parse_sql: Callable[..., Tree]) -> None:
    """Indexes cannot collide with tables or refer to missing, repeated or aliased columns."""
    for sql in (
        'CREATE TABLE t(x TEXT); CREATE INDEX T ON t(x);',
        'CREATE TABLE t(x TEXT); CREATE INDEX i ON absent(x);',
        'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(missing);',
        'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x,x);',
        'CREATE TABLE t(x TEXT, UNIQUE(missing));',
        'CREATE TABLE t(x TEXT PRIMARY KEY, y TEXT PRIMARY KEY);',
    ):
        with pytest.raises(SqlError):
            starting_schema(parse_sql(sql))
    schema = starting_schema(parse_sql('CREATE TABLE "T"("Key" TEXT PRIMARY KEY, b BIGINT);'
                                       'CREATE INDEX "I" ON "t"("KEY");'))
    assert schema[0].indexes[0].columns == ('key',)
    for sql in ('ALTER TABLE t ADD x BIGINT;', 'ALTER TABLE t ADD x TEXT NOT NULL;',
                'ALTER TABLE t ADD x TIMESTAMP DEFAULT CURRENT_TIMESTAMP;'):
        with pytest.raises(SqlError):
            statements(parse_sql(sql))
