"""Protect an optional associated schema without restricting reusable contracts."""

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from migration_check.baseline import check_baseline
from migration_check.diagnostics import Rejection


class SchemaBaselineTests(unittest.TestCase):
    """Compare actual input hashes, including missing and malformed schema pins."""

    def test_optional_schema_pin(self) -> None:
        """Only explicitly pinned schema hashes join the mandatory approved closure."""
        approved = {"approved/Requirements.lean": "a" * 64,
                    "approved/Interpretation.lean": "b" * 64}
        with TemporaryDirectory() as temporary:
            baseline = Path(temporary) / "baseline.json"
            baseline.write_text(json.dumps(approved))
            check_baseline(baseline, {**approved, "schema.sql": "c" * 64})
            pinned = {**approved, "schema.sql": "c" * 64}
            baseline.write_text(json.dumps(pinned))
            check_baseline(baseline, pinned)
            for actual in (approved, {**approved, "schema.sql": "d" * 64}):
                with self.assertRaisesRegex(Rejection, "schema.sql"):
                    check_baseline(baseline, actual)
            baseline.write_text(json.dumps({**approved, "schema.sql": "bad"}))
            with self.assertRaisesRegex(Rejection, "Invalid approved baseline hash"):
                check_baseline(baseline, pinned)


if __name__ == "__main__":
    unittest.main()
