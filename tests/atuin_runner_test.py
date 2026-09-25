"""Exercise native SQLx stage outcomes without assigning them proof status."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "conformance/atuin_capture"
SCENARIOS = ("success", "payload_failure", "metadata_insert_failure",
             "timing_update_failure", "dirty_metadata", "checksum_mismatch",
             "unknown_version", "already_applied")


class RunnerTest(unittest.TestCase):
    """Compare full native states before and after deliberate runner perturbations."""

    def test_stage_outcomes(self) -> None:
        """Retain all history bytes while distinguishing rollback and committed errors."""
        receipts = []
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as temp:
                migrations = Path(temp) / "migrations"
                shutil.copytree(CAPTURE / "migrations", migrations)
                if scenario == "payload_failure":
                    with (migrations / "20260709214605_shell.sql").open("a") as stream:
                        stream.write("INSERT INTO absent_table VALUES(1);\n")
                result = subprocess.run(
                    [str(ROOT / "build/atuin-cargo-target/debug/adversarial"),
                     str(Path(temp) / "history.db"), str(migrations), scenario],
                    capture_output=True, text=True, timeout=30, check=True)
                data = json.loads(result.stdout)
                self.assertEqual(data["profile"]["sqlite_version"], "3.46.0")
                self.assertEqual(data["history_before"], data["history_after"])
                self.assertEqual(data["history_before"], data["post_close_history"])
                self.assertEqual([r[0] for r in data["history_after"]], [-(2**63), -1, 2**63-1])
                self.assertEqual(data["history_after"][0][1:3], ["null", "NULL"])
                self.assertEqual(data["history_after"][1][1:3], ["null", "NULL"])
                self.assertEqual(data["history_after"][0][7], "text")
                self.assertEqual(data["history_after"][1][7], "real")
                self.assertEqual(data["history_after"][2][4], "blob")
                self.assertEqual(data["integrity_check"], "ok")
                self.assertEqual(data["post_close"]["metadata"], data["after"]["metadata"])
                for row in data["after"]["schema"]:
                    self.assertIn(row, data["post_close"]["schema"])
                extras = [row["name"] for row in data["post_close"]["schema"]
                          if row not in data["after"]["schema"]]
                self.assertEqual(extras, [])
                committed = scenario in ("success", "timing_update_failure", "already_applied")
                self.assertEqual(data["shell_nulls"], 3 if committed else None)
                error = data["error"]
                self.assertEqual(error is None, scenario in ("success", "already_applied"))
                reasons = {"payload_failure":"no such table: absent_table",
                    "metadata_insert_failure":"injected metadata insert failure",
                    "timing_update_failure":"injected timing update failure",
                    "dirty_metadata":"partially applied", "checksum_mismatch":"has been modified",
                    "unknown_version":"missing in the resolved migrations"}
                if scenario in reasons:
                    self.assertIn(reasons[scenario], error)
                old, new = data["before"], data["after"]
                if scenario not in ("success", "timing_update_failure"):
                    self.assertEqual(old, new)
                else:
                    self.assertEqual(new["metadata"][:-1], old["metadata"])
                    self.assertEqual(new["metadata"][-1]["version"], 20260709214605)
                    self.assertEqual(new["metadata"][-1]["success"], 1)
                    target = migrations / "20260709214605_shell.sql"
                    self.assertEqual(new["metadata"][-1]["checksum_hex"],
                                     hashlib.sha384(target.read_bytes()).hexdigest().upper())
                    if scenario == "timing_update_failure":
                        self.assertEqual(new["metadata"][-1]["execution_time"], -1)
                        self.assertIn("injected timing update failure", error)
                    for row in old["schema"]:
                        if row["name"] != "history":
                            self.assertIn(row, new["schema"])
                receipts.append({"scenario":scenario, "error":error,
                    "history_preserved":True, "shell_nulls":data["shell_nulls"],
                    "metadata_before":len(old["metadata"]),
                    "metadata_after":len(new["metadata"]), "integrity_check":"ok",
                    "post_close_added_objects":extras,
                    "statistics_tables":sorted(data["before"]["statistics"]),
                    "statistics_changed_on_close":data["post_close"]["statistics"]!=new["statistics"]})
        self.assertEqual(len(receipts), len(SCENARIOS))
        output = ROOT / "build/atuin-runner-receipts.json"
        output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps(receipts, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main()
