"""Admit generic literal writes and explicit transaction syntax without skipped CST branches."""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from belay.sqlite.profiles import profile
from belay.sqlite.sql_model import transition
from migration_check.lean_inputs import sql_inputs
from belay.sqlite.sql_tree import Tree
from belay.sqlite.sql_values import literal
from migration_check.lean_inputs import lean_value
from belay.sqlite.translate import starting_schema, statements

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]
SCHEMA = 'CREATE TABLE ledger(version BIGINT PRIMARY KEY, label TEXT, stamp TIMESTAMP, ok BOOLEAN, data BLOB);'


def test_both_grammars_preserve_all_explicit_operations(parse_sql: Callable[..., Tree]) -> None:
    """The generated script contains the transaction and each concrete write in order."""
    sql = ("BEGIN; INSERT INTO ledger(version,label,stamp,ok,data) "
           "VALUES(7,'can''t λ','2026-09-25 00:00:00',1,X'00ff'); COMMIT; "
           "UPDATE ledger SET ok=-1 WHERE version=7;")
    scripts = []
    for version in ('3.51.0', '3.46.0'):
        schema = starting_schema(parse_sql(SCHEMA, version))
        script = statements(parse_sql(sql, version))
        scripts.append(script)
        assert [item.kind for item in script] == ['beginTransaction', 'insert', 'commit', 'update']
        assert script[1].values == (7, "can't λ", '2026-09-25 00:00:00', 1, b'\0\xff')
        generated = sql_inputs(schema, script, profile(version))
        assert '.insert "ledger"' in generated
        assert '.update "ledger" "ok" (.integer (-1)) "version" (7)' in generated
        assert transition(schema, script) == (schema, '')
    assert scripts[0] == scripts[1]


def test_transaction_schema_effects_are_explicit(parse_sql: Callable[..., Tree]) -> None:
    """ROLLBACK restores schema while a pending transaction never implies a commit or rollback."""
    schema = starting_schema(parse_sql('CREATE TABLE t(x TEXT);'))
    for end, expected in (('ROLLBACK;', 1), ('COMMIT;', 2), ('', 2)):
        script = statements(parse_sql('BEGIN DEFERRED TRANSACTION; ALTER TABLE t ADD y TEXT;' + end))
        assert len(transition(schema, script)[0][0].columns) == expected
    assert transition(schema, statements(parse_sql('BEGIN; BEGIN;')))[1] == 'transactionAlreadyActive'
    assert transition(schema, statements(parse_sql('COMMIT;')))[1] == 'noActiveTransaction'


@pytest.mark.parametrize("sql,expected", [
    ('NULL', None), ('-9223372036854775808', -(2 ** 63)), ('+9223372036854775807', 2 ** 63 - 1),
    ('00007', 7), ("X''", b''), ("'a''b\\λ'", "a'b\\λ"),
])
def test_literal_storage_values(parse_sql: Callable[..., Tree], sql: str, expected: object) -> None:
    """Extreme int64, UTF-8, quoting and blobs retain their exact storage values."""
    parsed = parse_sql('SELECT ' + sql + ';')
    expression = next(node for node in parsed.walk(parsed.nodes[parsed.root]) if node.symbol == 'expr')
    assert literal(parsed, expression) == expected
    assert lean_value(expected).startswith('.')


@pytest.mark.parametrize("value", ['1.0', '9223372036854775808', '-9223372036854775809', '1+2', '?',
                                   'CURRENT_TIMESTAMP', 'TRUE', '0x10', "CAST('7' AS INTEGER)"])
def test_unsupported_literal_expressions_reject(parse_sql: Callable[..., Tree], value: str) -> None:
    """Values outside the exact literal subset cannot be written."""
    with pytest.raises(SqlError):
        statements(parse_sql(f'INSERT INTO t(x) VALUES({value});'))


@pytest.mark.parametrize("schema_sql,sql", [
    ('CREATE TABLE t(k TEXT PRIMARY KEY,x TEXT);', "INSERT INTO t(k,x) VALUES('key','x');"),
    ('CREATE TABLE t(k BIGINT,x NUMERIC,UNIQUE(k,x));', 'UPDATE t SET x=2 WHERE k=1;'),
    ('CREATE TABLE t(k BIGINT PRIMARY KEY,x TEXT);', "INSERT INTO t(k,x) VALUES(X'01','x');"),
    ('CREATE TABLE t(k BIGINT PRIMARY KEY,x TEXT);', "UPDATE t SET k=X'01' WHERE k=1;"),
    ('CREATE TABLE t(k INTEGER,x TEXT);', "UPDATE t SET x='x' WHERE k=1;"),
])
def test_unmodeled_key_comparisons_reject(parse_sql: Callable[..., Tree], schema_sql: str, sql: str) -> None:
    """The static key domain cannot be smuggled into a false runtime-error claim."""
    schema = starting_schema(parse_sql(schema_sql))
    with pytest.raises(SqlError):
        sql_inputs(schema, statements(parse_sql(sql)))


def test_unique_index_key_update_is_admitted(parse_sql: Callable[..., Tree]) -> None:
    """An update keyed by a unique-indexed integer column stays inside the modeled domain."""
    schema = starting_schema(parse_sql('CREATE TABLE t(k BIGINT,x TEXT); CREATE UNIQUE INDEX kidx ON t(k);'))
    assert '.update' in sql_inputs(schema, statements(parse_sql("UPDATE t SET x='ok' WHERE k=1;")))


@pytest.mark.parametrize("sql", [
    'BEGIN IMMEDIATE;', 'SAVEPOINT a;', 'ROLLBACK TO a;',
    'INSERT OR REPLACE INTO t(x) VALUES(1);', 'INSERT INTO t DEFAULT VALUES;',
    'INSERT INTO t(x) VALUES(1),(2);', 'INSERT INTO t(x) SELECT 1;',
    'INSERT INTO t(x) VALUES(1) RETURNING x;',
    'UPDATE t SET x=1;', 'UPDATE t SET x=1,y=2 WHERE id=1;',
    'UPDATE t SET x=1 WHERE id=1 OR id=2;', 'UPDATE t SET x=1 WHERE id IS NULL;',
])
def test_optional_syntax_rejects(parse_sql: Callable[..., Tree], sql: str) -> None:
    """Optional grammar branches outside the lossless subset reject during translation."""
    with pytest.raises(SqlError):
        statements(parse_sql(sql))


@pytest.mark.parametrize("sql", [
    "INSERT INTO t(id,x,y,z) VALUES(1,2,3,NULL);",
    "INSERT INTO t(id,x,y,z) VALUES(1,'ok','123',NULL);",
    "INSERT INTO t(id,x,y,z) VALUES(1,'ok',3,1);",
    "INSERT INTO t(id,x) VALUES(1,'ok');",
    "INSERT INTO t(x,id,y,z) VALUES('ok',1,3,NULL);",
    'UPDATE t SET x=1 WHERE id=1;', 'UPDATE t SET missing=NULL WHERE id=1;',
])
def test_coercing_writes_are_unsupported(parse_sql: Callable[..., Tree], sql: str) -> None:
    """Writes that would need affinity coercion or omit columns are UNSUPPORTED."""
    schema = starting_schema(parse_sql('CREATE TABLE t(id INTEGER,x TEXT,y NUMERIC,z REAL);'))
    with pytest.raises(SqlError) as rejected:
        sql_inputs(schema, statements(parse_sql(sql)))
    assert rejected.value.status == 'UNSUPPORTED'
