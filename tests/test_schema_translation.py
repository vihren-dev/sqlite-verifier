"""Real-parser regression coverage for rich declarative baselines and narrow migrations."""

import unittest

from migration_check.diagnostics import Rejection
from migration_check.sql_model import sql_inputs, transition
from migration_check.translate import starting_schema, statements
from tests.test_translation import tree

BASELINE = """
CREATE INDEX event_time ON events(occurred);
CREATE TABLE events(id TEXT PRIMARY KEY, occurred INTEGER NOT NULL, message TEXT NOT NULL,
                    author TEXT, UNIQUE(occurred, message));
CREATE UNIQUE INDEX author_message ON events(author, message);
CREATE TABLE ledger(version BIGINT PRIMARY KEY, description TEXT NOT NULL,
                    installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    success BOOLEAN NOT NULL, checksum BLOB NOT NULL, execution_time BIGINT NOT NULL);
"""


class SchemaTranslationTests(unittest.TestCase):
    """Assert preserved schema structure and complete rejection of unmodeled dependencies."""

    def test_metadata_and_indexes_survive_nullable_add(self) -> None:
        """Metadata and ordered key projections remain unchanged while ADD appends NULL storage."""
        schema = starting_schema(tree(BASELINE))
        events, ledger = schema
        self.assertEqual(events.primary_key, ("id",))
        self.assertFalse(events.columns[0].not_null)
        self.assertEqual(events.unique_keys, (("occurred", "message"),))
        self.assertEqual([index.name for index in events.indexes], ["event_time", "author_message"])
        self.assertTrue(events.indexes[1].unique)
        self.assertEqual(ledger.columns[0].declared_type, "bigInt")
        self.assertEqual(ledger.columns[2].affinity, "numeric")
        self.assertTrue(ledger.columns[2].current_timestamp)
        self.assertTrue(ledger.columns[2].not_null)
        self.assertEqual(ledger.columns[3].declared_type, "boolean")
        script = statements(tree('ALTER TABLE events ADD extra TEXT;'))
        after, failure = transition(schema, script)
        self.assertFalse(failure)
        self.assertEqual(after[0].indexes, events.indexes)
        self.assertEqual(after[0].primary_key, events.primary_key)
        self.assertEqual(after[0].unique_keys, events.unique_keys)
        self.assertEqual(after[0].columns[:-1], events.columns)
        self.assertEqual(after[1], ledger)
        generated = sql_inputs(schema, script)
        for binding in ('declaredType := .bigInt', 'notNull := true',
                        'defaultValue := some .currentTimestamp', 'primaryKey := ["id"]',
                        'name := "author_message"', 'unique := true'):
            self.assertIn(binding, generated)
        changed = starting_schema(tree(BASELINE.replace('UNIQUE(occurred, message)', 'UNIQUE(message, occurred)')))
        self.assertNotEqual(sql_inputs(changed, script), generated)
        with self.assertRaises(Rejection):
            sql_inputs(schema, statements(tree('CREATE TABLE unrelated(x TEXT);')))

    def test_create_cannot_collide_with_preserved_index(self) -> None:
        """The model's table-only CREATE primitive cannot bypass SQLite's shared namespace."""
        schema = starting_schema(tree('CREATE TABLE t(a TEXT); CREATE INDEX other ON t(a);'))
        with self.assertRaises(Rejection) as rejected:
            sql_inputs(schema, statements(tree('CREATE TABLE other(x TEXT);')))
        self.assertEqual(rejected.exception.status, 'UNSUPPORTED')

    def test_unsupported_metadata_cannot_disappear(self) -> None:
        """Every optional clause outside the fixed structural subset must reject."""
        cases = [
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
        for sql in cases:
            with self.subTest(sql=sql), self.assertRaises(Rejection) as rejected:
                starting_schema(tree(sql))
            self.assertEqual(rejected.exception.status, 'UNSUPPORTED')

    def test_statistics_are_exact_engine_managed_baseline_objects(self) -> None:
        """No arbitrary reserved table or modified optimizer metadata enters the baseline."""
        statistics = ('CREATE TABLE sqlite_stat1(tbl,idx,stat);'
                      'CREATE TABLE sqlite_stat4(tbl,idx,neq,nlt,ndlt,sample);')
        schema = starting_schema(tree(statistics))
        self.assertEqual([table.name for table in schema], ['sqlite_stat1', 'sqlite_stat4'])
        self.assertTrue(all(column.declared_type == 'untyped' and column.affinity == 'blob'
                            for table in schema for column in table.columns))
        self.assertEqual(starting_schema(tree('CREATE TABLE ordinary(x);'))[0].columns[0].declared_type,
                         'untyped')
        for sql in ('CREATE TABLE sqlite_unknown(x);', 'CREATE TABLE sqlite_stat1(tbl,idx,stat TEXT);',
                    'CREATE TABLE sqlite_stat1(tbl,idx,stat,extra);',
                    'CREATE TABLE sqlite_stat1(tbl,idx,stat NOT NULL);',
                    'CREATE TABLE sqlite_stat4(tbl,idx,neq,nlt,sample,ndlt);'):
            with self.subTest(sql=sql), self.assertRaises(Rejection):
                starting_schema(tree(sql))
        for sql in ('ALTER TABLE sqlite_stat1 ADD extra TEXT;', 'ALTER TABLE ordinary ADD extra;'):
            with self.subTest(sql=sql), self.assertRaises(Rejection):
                statements(tree(sql))

    def test_global_namespace_references_and_aliases(self) -> None:
        """Indexes cannot collide with tables or refer to missing, repeated or aliased columns."""
        for sql in (
            'CREATE TABLE t(x TEXT); CREATE INDEX T ON t(x);',
            'CREATE TABLE t(x TEXT); CREATE INDEX i ON absent(x);',
            'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(missing);',
            'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x,x);',
            'CREATE TABLE t(x TEXT, UNIQUE(missing));',
            'CREATE TABLE t(x TEXT PRIMARY KEY, y TEXT PRIMARY KEY);',
        ):
            with self.subTest(sql=sql), self.assertRaises(Rejection):
                starting_schema(tree(sql))
        schema = starting_schema(tree('CREATE TABLE "T"("Key" TEXT PRIMARY KEY, b BIGINT);'
                                     'CREATE INDEX "I" ON "t"("KEY");'))
        self.assertEqual(schema[0].indexes[0].columns, ('key',))
        for sql in ('ALTER TABLE t ADD x BIGINT;', 'ALTER TABLE t ADD x TEXT NOT NULL;',
                    'ALTER TABLE t ADD x TIMESTAMP DEFAULT CURRENT_TIMESTAMP;'):
            with self.subTest(sql=sql), self.assertRaises(Rejection):
                statements(tree(sql))


if __name__ == '__main__':
    unittest.main()
