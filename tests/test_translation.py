"""End-to-end admission checks against the production upstream-derived parser."""

from pathlib import Path
import unittest

from migration_check.diagnostics import Rejection
from migration_check.sql_model import lean_string, sql_inputs, transition
from migration_check.sql_tree import Tree, parse
from migration_check.translate import normalize, starting_schema, statements

PARSER = Path(__file__).resolve().parent.parent / "build/sqlite-parser"


def tree(sql: str) -> Tree:
    """Use the real grammar for every semantic-admission regression."""
    return parse(PARSER, sql.encode(), "fixture.sql")


class TranslationTests(unittest.TestCase):
    """Protect statement completeness, naming rules, and prefix error behavior."""

    def test_supported_scripts_and_prefix_failures(self) -> None:
        """Quoted names and comments keep byte spans and sequential name resolution."""
        schema = starting_schema(tree('CREATE TABLE "Café"("Имя" TEXT, n INTEGER);'))
        sql = '/* ; */ ALTER TABLE "Café" ADD "💡" BLOB; CREATE TABLE extra(r REAL, n NUMERIC);'
        script = statements(tree(sql))
        after, failure = transition(schema, script)
        self.assertEqual(failure, "")
        self.assertEqual([table.name for table in after], ["café", "extra"])
        self.assertEqual(after[0].columns[-1].name, "💡")
        self.assertEqual(len(script), 2)
        self.assertTrue(sql.encode()[script[0].start:script[0].end].startswith(b"ALTER TABLE"))
        broken = statements(tree('ALTER TABLE "Café" ADD new TEXT; CREATE TABLE "CAFé"(x TEXT);'
                                 'CREATE TABLE skipped(x TEXT);'))
        prefix, error = transition(schema, broken)
        self.assertEqual(error, "tableExists")
        self.assertEqual(len(prefix), 1)
        self.assertEqual(prefix[0].columns[-1].name, "new")
        self.assertEqual(transition(schema, statements(tree('ALTER TABLE absent ADD x TEXT;')))[1],
                         "missingTable")
        self.assertEqual(transition(schema, statements(tree('ALTER TABLE "café" ADD N TEXT;')))[1],
                         "columnExists")
        self.assertIn('def script : List Statement := [.addColumn "café"', sql_inputs(schema, script))
        self.assertEqual(normalize("ÄZ"), "Äz")
        self.assertEqual(lean_string('a\b\f"\\\n'), '"a\\u0008\\u000c\\"\\\\\\u000a"')

    def test_unsupported_dependencies_and_definitions(self) -> None:
        """No valid but unmodeled object or optional SQL clause can disappear."""
        cases = [
            'CREATE TABLE t(x INTEGER PRIMARY KEY);', 'CREATE TABLE t(x);',
            'CREATE TABLE t(x VARCHAR(20));', 'CREATE TABLE t(x "TEXT");',
            'CREATE TABLE t(x TEXT NOT NULL);', 'CREATE TABLE t(x TEXT DEFAULT NULL);',
            'CREATE TABLE t(x TEXT COLLATE NOCASE);', 'CREATE TABLE t(x TEXT UNIQUE);',
            'CREATE TABLE t(x TEXT REFERENCES u);', 'CREATE TABLE t(x TEXT CHECK(x));',
            'CREATE TABLE t(x TEXT, UNIQUE(x));', 'CREATE TABLE t(x TEXT) STRICT;',
            'CREATE TEMP TABLE t(x TEXT);', 'CREATE TABLE main.t(x TEXT);',
            'CREATE TABLE IF NOT EXISTS t(x TEXT);', 'CREATE TABLE t AS SELECT 1;',
            'CREATE TABLE t(rowid TEXT);', 'CREATE TABLE sqlite_private(x TEXT);',
            'CREATE TABLE t(x TEXT, X TEXT);', 'ALTER TABLE main.t ADD x TEXT;',
            'ALTER TABLE t RENAME TO u;', 'ALTER TABLE t ADD x TEXT GENERATED AS (1);',
            'CREATE TABLE t(x TEXT); CREATE VIEW v AS SELECT * FROM t;',
            'CREATE TABLE t(x TEXT); CREATE INDEX i ON t(x);',
            'CREATE TABLE t(x TEXT); CREATE TRIGGER tr AFTER INSERT ON t BEGIN SELECT 1; END;',
            'PRAGMA foreign_keys=ON;', 'BEGIN IMMEDIATE; CREATE TABLE t(x TEXT); COMMIT;',
            'EXPLAIN CREATE TABLE t(x TEXT);', 'SELECT 1;',
        ]
        for sql in cases:
            with self.subTest(sql=sql), self.assertRaises(Rejection) as rejected:
                statements(tree(sql))
            self.assertEqual(rejected.exception.status, "UNSUPPORTED")
        with self.assertRaises(Rejection) as duplicate:
            starting_schema(tree('CREATE TABLE t(x TEXT); CREATE TABLE T(x TEXT);'))
        self.assertEqual(duplicate.exception.status, "INPUT_ERROR")
        self.assertEqual(starting_schema(tree('-- empty\n;')), ())

    def test_wrong_parser_profile_is_rejected(self) -> None:
        """Selecting a different engine cannot silently consume the current grammar binary."""
        with self.assertRaises(Rejection) as rejected:
            parse(PARSER, b'CREATE TABLE t(x TEXT);', 'fixture.sql', expected_profile='3.46.0')
        self.assertEqual(rejected.exception.status, 'UNVERIFIED')
        self.assertIn('profile mismatch', str(rejected.exception))

    def test_parser_failure_classes(self) -> None:
        """Resource exhaustion does not become a syntax error or a violated theorem."""
        for sql, status in [("CREATE TABLE", "INPUT_ERROR"), (" " * (1024 * 1024 + 1), "UNVERIFIED")]:
            with self.assertRaises(Rejection) as rejected:
                tree(sql)
            self.assertEqual(rejected.exception.status, status)


if __name__ == "__main__":
    unittest.main()
