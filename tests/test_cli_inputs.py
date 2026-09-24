"""Check fast user-facing input diagnostics before any proof process can run."""

import contextlib
import io
import json
from pathlib import Path
import unittest

from migration_check.cli import main


class InputTests(unittest.TestCase):
    """Required/malformed/unsupported profile distinctions are part of the public API."""

    def test_profile_diagnostics(self) -> None:
        """Invalid profiles fail consistently without requiring source files or installed artifacts."""
        common = ["verify", "--format", "json"]
        for name in ("schema", "interpretation", "migration", "next-interpretation", "requirements", "proofs"):
            common.extend(["--" + name, str(Path("missing") / name)])
        for suffix, status in [([], "INPUT_ERROR"), (["--profile", "latest"], "INPUT_ERROR"),
                               (["--profile", "3.50.0"], "UNSUPPORTED")]:
            with self.subTest(suffix=suffix), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main([*common, *suffix]), 1)
            self.assertEqual(json.loads(output.getvalue())["status"], status)


if __name__ == "__main__":
    unittest.main()
