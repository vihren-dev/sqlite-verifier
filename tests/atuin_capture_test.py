"""Check complete real-runner exports and immutable upstream migration identity."""
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "conformance/atuin_capture"
BINARY = ROOT / "build/atuin-cargo-target/debug/atuin-sqlx-capture"


class CaptureTest(unittest.TestCase):
    """Test evidence with the pinned native runner, not another SQLite library."""

    def test_capture_and_provenance(self) -> None:
        """Reproduce all schema objects and verify SQLx's original byte checksums."""
        provenance = json.loads((CAPTURE / "provenance.json").read_text())
        lock = tomllib.loads((CAPTURE / "Cargo.lock").read_text())
        identities = [{k: p[k] for k in ("name", "version", "checksum")}
                      for p in lock["package"] if "checksum" in p]
        self.assertEqual(identities, provenance["resolved_registry_packages_from_upstream_lock"])
        for name, digest in provenance["migration_sha256"].items():
            self.assertEqual(hashlib.sha256((CAPTURE / "migrations" / name).read_bytes()).hexdigest(), digest)
        with tempfile.TemporaryDirectory(prefix="atuin-capture-test-") as directory:
            command = [str(BINARY), str(Path(directory) / "history.db"), str(CAPTURE / "migrations")]
            result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=True)
            actual = json.loads(result.stdout)
            expected = json.loads((CAPTURE / "capture.json").read_text())
            self.assertEqual(actual["profile"]["sqlite_source_id"], expected["profile"]["sqlite_source_id"])
            self.assertEqual(actual["profile"]["pragmas"], expected["profile"]["pragmas"])
            self.assertEqual(actual["profile"]["compile_options"], expected["profile"]["compile_options"])
            self.assertEqual(actual["profile"]["runtime_limits"], expected["profile"]["runtime_limits"])
            self.assertEqual(actual["post_close"]["schema"], expected["post_close"]["schema"])
            self.assertEqual(len(actual["post_close"]["schema"]), 10)
            self.assertEqual(actual["persisted_baseline"], actual["before"])
            self.assertEqual(actual["after"]["schema"], actual["post_close"]["schema"])
            for stage, count in (("before", 6), ("after", 7)):
                self.assertEqual(actual[stage]["schema"], expected[stage]["schema"])
                self.assertEqual(len(actual[stage]["schema"]), 10)
                self.assertEqual(len(actual[stage]["metadata"]), count)
                ddl = [row["sql"] + ";" for kind in ("table", "index")
                       for row in actual[stage]["schema"]
                       if row["type"] == kind and row["sql"] is not None]
                self.assertEqual((CAPTURE / f"{stage}.sql").read_text(), "\n\n".join(ddl) + "\n")
                for row in actual[stage]["metadata"]:
                    files = list((CAPTURE / "migrations").glob(f"{row['version']}_*.sql"))
                    self.assertEqual(len(files), 1)
                    self.assertEqual(row["checksum_hex"], hashlib.sha384(files[0].read_bytes()).hexdigest().upper())
                    self.assertEqual(row["success"], 1)
                    self.assertGreaterEqual(row["execution_time"], 0)
            refused = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("refuses to overwrite", refused.stderr)


if __name__ == "__main__":
    unittest.main()
