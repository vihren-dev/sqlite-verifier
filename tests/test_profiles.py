"""Strict profile input binding, independent of candidate claims and printed output."""

import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from migration_check.diagnostics import Rejection
from migration_check.profiles import LEGACY_PROFILE, SQLX_KIND, profile
from migration_check.sql_model import sql_inputs
from migration_check.translate import starting_schema, statements
from tests.test_translation import tree


def manifest() -> dict[str, object]:
    """A small generic catalog avoids coupling profile support to the pilot fixture."""
    return {'kind': SQLX_KIND, 'migration': {'version': 20, 'description': 'new column λ'},
            'previous': [{'version': 10, 'checksum': 'ab' * 48}]}


class ProfileTests(unittest.TestCase):
    """Only exact reviewed configuration can choose a runner or alter the sealed target."""

    def test_exact_binding_and_checksum_from_sql(self) -> None:
        """Both whitespace changes and catalog changes alter the sealed source binding."""
        self.assertEqual(profile('3.51.0'), LEGACY_PROFILE)
        with TemporaryDirectory() as temporary:
            path = Path(temporary) / 'profile.json'
            raw = json.dumps(manifest()).encode()
            path.write_bytes(raw)
            selected = profile(str(path))
            self.assertEqual(selected.engine, '3.46.0')
            self.assertEqual(selected.source_digest, hashlib.sha256(raw).hexdigest())
            schema = starting_schema(tree('CREATE TABLE records(x TEXT);'))
            sql = b'ALTER TABLE records ADD y TEXT;'
            script = statements(tree(sql.decode()))
            generated = sql_inputs(schema, script, selected, sql)
            self.assertIn('def profile : ExecutionProfile := .sqlite346Sqlx', generated)
            expected = ', '.join(map(str, hashlib.sha384(sql).digest()))
            self.assertIn('checksum := [' + expected + ']', generated)
            self.assertNotEqual(generated, sql_inputs(schema, script, selected, sql + b'\n'))
            self.assertIn('def profile : ExecutionProfile := .sqlite351Autocommit', sql_inputs(schema, script))
            with self.assertRaises(ValueError):
                sql_inputs(schema, script, selected)
            directive = b'-- no-transaction\n' + sql
            with self.assertRaises(Rejection) as rejected:
                sql_inputs(schema, statements(tree(directive.decode())), selected, directive)
            self.assertEqual(rejected.exception.status, 'UNSUPPORTED')
            # SQLx checks the exact prefix; whitespace/case changes do not opt out.
            for prefix in (b' -- no-transaction\n', b'-- NO-TRANSACTION\n'):
                self.assertIn('.sqlite346Sqlx', sql_inputs(schema, script, selected, prefix + sql))
            for command in ('CREATE TABLE new_table(x TEXT);',
                            'ALTER TABLE _sqlx_migrations ADD extra TEXT;'):
                with self.subTest(command=command), self.assertRaises(Rejection) as rejected:
                    sql_inputs(schema, statements(tree(command)), selected, command.encode())
                self.assertEqual(rejected.exception.status, 'UNSUPPORTED')

    def test_unknown_fields_and_invalid_catalog_reject(self) -> None:
        """No bool-version, oversized integer, duplicate key or configuration drift is accepted."""
        base = manifest()
        variants: list[object] = [
            {**base, 'foreign_keys': False}, {**base, 'kind': 'sqlite-3.46.0-other'},
            {**base, 'migration': {'version': True, 'description': 'x'}},
            {**base, 'migration': {'version': 2 ** 63, 'description': 'x'}},
            {**base, 'migration': {'version': 20, 'description': 'x', 'checksum': '00' * 48}},
            {**base, 'migration': {'version': 20, 'description': 1}},
            {**base, 'previous': [{'version': 10, 'checksum': 'ab' * 47}]},
            {**base, 'previous': [{'version': 10, 'checksum': 'zz' * 48}]},
            {**base, 'previous': [{'version': 20, 'checksum': 'ab' * 48}]},
            {**base, 'previous': [{'version': 21, 'checksum': 'ab' * 48}]},
            {**base, 'previous': [{'version': 10, 'checksum': 'ab' * 48},
                                  {'version': 10, 'checksum': 'ab' * 48}]},
            {**base, 'previous': [{'version': 11, 'checksum': 'ab' * 48},
                                  {'version': 10, 'checksum': 'ab' * 48}]},
            {**base, 'previous': {}}, [], {'kind': SQLX_KIND},
        ]
        with TemporaryDirectory() as temporary:
            path = Path(temporary) / 'profile.json'
            for variant in variants:
                path.write_text(json.dumps(variant))
                with self.subTest(variant=variant), self.assertRaises(Rejection):
                    profile(str(path))
            path.write_text('{"kind":"x","kind":"y","migration":{},"previous":[]}')
            with self.assertRaises(Rejection) as duplicate:
                profile(str(path))
            self.assertIn('Duplicate', str(duplicate.exception))
            path.write_text('[' * 2000)
            with self.assertRaises(Rejection):
                profile(str(path))
        with self.assertRaises(Rejection) as bare_engine:
            profile('3.46.0')
        self.assertEqual(bare_engine.exception.status, 'UNSUPPORTED')


if __name__ == '__main__':
    unittest.main()
