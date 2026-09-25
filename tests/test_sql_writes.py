"""Admit generic literal writes and explicit transaction syntax without skipped CST branches."""

from pathlib import Path
import unittest

from migration_check.diagnostics import Rejection
from migration_check.profiles import profile
from migration_check.sql_model import sql_inputs, transition
from migration_check.sql_tree import Tree, parse
from migration_check.sql_values import literal, lean_value
from migration_check.translate import starting_schema, statements

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 'CREATE TABLE ledger(version BIGINT PRIMARY KEY, label TEXT, stamp TIMESTAMP, ok BOOLEAN, data BLOB);'


def tree(sql: str, version: str = '3.51.0') -> Tree:
    """Use the actual pinned native grammar under the selected engine version."""
    binary = 'sqlite-parser' if version == '3.51.0' else 'sqlite-parser-3.46.0'
    return parse(ROOT / 'build' / binary, sql.encode(), 'literal.sql', version)


class LiteralWriteTests(unittest.TestCase):
    """Examples use neutral table names; no pilot-specific admission or catalog handling exists."""

    def test_both_grammars_preserve_all_explicit_operations(self) -> None:
        """The generated script contains the transaction and each concrete write in order."""
        sql = ("BEGIN; INSERT INTO ledger(version,label,stamp,ok,data) "
               "VALUES(7,'can''t λ','2026-09-25 00:00:00',1,X'00ff'); COMMIT; "
               "UPDATE ledger SET ok=-1 WHERE version=7;")
        scripts = []
        for version in ('3.51.0', '3.46.0'):
            schema = starting_schema(tree(SCHEMA, version))
            script = statements(tree(sql, version))
            scripts.append(script)
            self.assertEqual([item.kind for item in script], ['beginTransaction', 'insert', 'commit', 'update'])
            self.assertEqual(script[1].values, (7, "can't λ", '2026-09-25 00:00:00', 1, b'\0\xff'))
            generated = sql_inputs(schema, script, profile(version))
            self.assertIn('.insert "ledger"', generated)
            self.assertIn('.update "ledger" "ok" (.integer (-1)) "version" (7)', generated)
            self.assertEqual(transition(schema, script), (schema, ''))
        self.assertEqual(scripts[0], scripts[1])

    def test_transaction_schema_effects_are_explicit(self) -> None:
        """ROLLBACK restores schema while a pending transaction never implies a commit or rollback."""
        schema = starting_schema(tree('CREATE TABLE t(x TEXT);'))
        for end, expected in (('ROLLBACK;', 1), ('COMMIT;', 2), ('', 2)):
            script = statements(tree('BEGIN DEFERRED TRANSACTION; ALTER TABLE t ADD y TEXT;' + end))
            self.assertEqual(len(transition(schema, script)[0][0].columns), expected)
        self.assertEqual(transition(schema, statements(tree('BEGIN; BEGIN;')))[1], 'transactionAlreadyActive')
        self.assertEqual(transition(schema, statements(tree('COMMIT;')))[1], 'noActiveTransaction')

    def test_literal_storage_and_unsupported_expressions(self) -> None:
        """Extreme int64, UTF-8, quoting and blobs retain their exact storage values."""
        examples = [('NULL', None), ('-9223372036854775808', -(2 ** 63)),
                    ('+9223372036854775807', 2 ** 63 - 1), ('00007', 7), ("X''", b''),
                    ("'a''b\\λ'", "a'b\\λ")]
        for sql, expected in examples:
            parsed = tree('SELECT ' + sql + ';')
            expression = next(node for node in parsed.walk(parsed.nodes[parsed.root]) if node.symbol == 'expr')
            self.assertEqual(literal(parsed, expression), expected)
            self.assertTrue(lean_value(expected).startswith('.'))
        for value in ('1.0', '9223372036854775808', '-9223372036854775809', '1+2', '?',
                      'CURRENT_TIMESTAMP', 'TRUE', '0x10', "CAST('7' AS INTEGER)"):
            with self.subTest(value=value), self.assertRaises(Rejection):
                statements(tree(f'INSERT INTO t(x) VALUES({value});'))

    def test_unmodeled_key_comparisons_reject(self) -> None:
        """The static key domain cannot be smuggled into a false runtime-error claim."""
        cases = [
            ('CREATE TABLE t(k TEXT PRIMARY KEY,x TEXT);', "INSERT INTO t(k,x) VALUES('key','x');"),
            ('CREATE TABLE t(k BIGINT,x NUMERIC,UNIQUE(k,x));', 'UPDATE t SET x=2 WHERE k=1;'),
            ('CREATE TABLE t(k BIGINT PRIMARY KEY,x TEXT);', "INSERT INTO t(k,x) VALUES(X'01','x');"),
            ('CREATE TABLE t(k BIGINT PRIMARY KEY,x TEXT);', "UPDATE t SET k=X'01' WHERE k=1;"),
            ('CREATE TABLE t(k INTEGER,x TEXT);', "UPDATE t SET x='x' WHERE k=1;"),
        ]
        for schema_sql, sql in cases:
            schema = starting_schema(tree(schema_sql))
            with self.subTest(sql=sql), self.assertRaises(Rejection):
                sql_inputs(schema, statements(tree(sql)))
        schema = starting_schema(tree('CREATE TABLE t(k BIGINT,x TEXT); CREATE UNIQUE INDEX kidx ON t(k);'))
        self.assertIn('.update', sql_inputs(schema, statements(tree("UPDATE t SET x='ok' WHERE k=1;"))))

    def test_optional_syntax_and_coercions_reject(self) -> None:
        """Reject optional grammar branches and every write outside the lossless subset."""
        for sql in ('BEGIN IMMEDIATE;', 'SAVEPOINT a;', 'ROLLBACK TO a;',
                    'INSERT OR REPLACE INTO t(x) VALUES(1);', 'INSERT INTO t DEFAULT VALUES;',
                    'INSERT INTO t(x) VALUES(1),(2);', 'INSERT INTO t(x) SELECT 1;',
                    'INSERT INTO t(x) VALUES(1) RETURNING x;',
                    'UPDATE t SET x=1;', 'UPDATE t SET x=1,y=2 WHERE id=1;',
                    'UPDATE t SET x=1 WHERE id=1 OR id=2;', 'UPDATE t SET x=1 WHERE id IS NULL;'):
            with self.subTest(sql=sql), self.assertRaises(Rejection):
                statements(tree(sql))
        schema = starting_schema(tree('CREATE TABLE t(id INTEGER,x TEXT,y NUMERIC,z REAL);'))
        for sql in ("INSERT INTO t(id,x,y,z) VALUES(1,2,3,NULL);",
                    "INSERT INTO t(id,x,y,z) VALUES(1,'ok','123',NULL);",
                    "INSERT INTO t(id,x,y,z) VALUES(1,'ok',3,1);",
                    "INSERT INTO t(id,x) VALUES(1,'ok');",
                    "INSERT INTO t(x,id,y,z) VALUES('ok',1,3,NULL);",
                    'UPDATE t SET x=1 WHERE id=1;', 'UPDATE t SET missing=NULL WHERE id=1;'):
            with self.subTest(sql=sql), self.assertRaises(Rejection) as rejected:
                sql_inputs(schema, statements(tree(sql)))
            self.assertEqual(rejected.exception.status, 'UNSUPPORTED')


if __name__ == '__main__':
    unittest.main()
