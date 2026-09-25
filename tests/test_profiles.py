"""Version-only SQLite settings never introduce application catalogs or SQL operations."""

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from migration_check.diagnostics import Rejection
from migration_check.profiles import LEGACY_PROFILE, profile
from migration_check.sql_model import sql_inputs
from migration_check.translate import starting_schema, statements
from tests.test_translation import tree


class ProfileTests(unittest.TestCase):
    """Separate engine binding from the explicit SQL and approved application assumptions."""

    def test_versions_have_distinct_sealed_bindings(self) -> None:
        """Both supported releases admit ordinary SQL and bind distinct constructors."""
        self.assertEqual(profile('3.51.0'), LEGACY_PROFILE)
        schema = starting_schema(tree('CREATE TABLE records(x TEXT);'))
        script = statements(tree('ALTER TABLE records ADD y TEXT;'))
        generated = [sql_inputs(schema, script, profile(version)) for version in ('3.51.0', '3.46.0')]
        self.assertIn('def profile : ExecutionProfile := .sqlite351', generated[0])
        self.assertIn('def profile : ExecutionProfile := .sqlite346', generated[1])
        self.assertNotEqual(*generated)
        self.assertEqual(generated[0].replace('.sqlite351', '.sqlite346'), generated[1])

    def test_no_framework_directives_or_reserved_catalog_names(self) -> None:
        """Comments stay comments, and application bookkeeping names are ordinary tables."""
        selected = profile('3.46.0')
        schema = starting_schema(tree('CREATE TABLE _sqlx_migrations(x TEXT);'))
        plain = statements(tree('ALTER TABLE _sqlx_migrations ADD y TEXT;'))
        commented = statements(tree('-- no-transaction\nALTER TABLE _sqlx_migrations ADD y TEXT;'))
        self.assertEqual(sql_inputs(schema, plain, selected), sql_inputs(schema, commented, selected))
        self.assertIn('.createTable', sql_inputs((), statements(tree('CREATE TABLE t(x TEXT);')), selected))

    def test_catalog_json_and_unknown_versions_reject(self) -> None:
        """Neither existing manifest files nor application identities can select implicit behavior."""
        with TemporaryDirectory() as directory:
            manifest = Path(directory) / 'profile.json'
            manifest.write_text('{"kind":"sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1",'
                                '"migration":{"version":7,"description":"x"},"previous":[]}')
            for value in (str(manifest), manifest.read_text(), '', '3.46', ' 3.46.0'):
                with self.subTest(value=value), self.assertRaises(Rejection) as rejected:
                    profile(value)
                self.assertEqual(rejected.exception.status, 'INPUT_ERROR')
        with self.assertRaises(Rejection) as rejected:
            profile('3.45.0')
        self.assertEqual(rejected.exception.status, 'UNSUPPORTED')


if __name__ == '__main__':
    unittest.main()
