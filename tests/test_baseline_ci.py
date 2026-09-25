"""Exercise target-owned baseline checks against adversarial candidate Git objects."""

import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest

from tests.baseline_ci import APPROVED_ROOTS, SCHEMA_PATHS, check, git


class BaselineProtectionTest(unittest.TestCase):
    """A candidate cannot approve changed sources by editing its own manifest or checker."""

    def test_source_and_manifest_drift(self) -> None:
        """Pin complete source sets, including transitive helpers, in the target branch."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            git(root, "init", "-q")
            for directory in APPROVED_ROOTS:
                approved = root / directory
                approved.mkdir(parents=True)
                for name in ("Requirements", "Interpretation", "Helper"):
                    (approved / f"{name}.lean").write_text(f"-- {name}\n", encoding="utf-8")
                hashes = {f"approved/{path.name}": hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in approved.glob("*.lean")}
                schema = root / SCHEMA_PATHS[directory]
                schema.write_text("CREATE TABLE history(command TEXT);\n", encoding="utf-8")
                hashes["schema.sql"] = hashlib.sha256(schema.read_bytes()).hexdigest()
                (approved / "baseline.json").write_text(json.dumps(hashes), encoding="utf-8")

            def commit() -> str:
                """Create a bounded local fixture revision without repository hooks."""
                git(root, "add", ".")
                git(root, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
                return git(root, "rev-parse", "HEAD").decode().strip()

            base = commit()
            check(root, base, base)
            for directory in APPROVED_ROOTS:
                schema = root / SCHEMA_PATHS[directory]
                schema.write_text("CREATE TABLE history(command BLOB);\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "schema.sql"):
                    check(root, base, commit())
                git(root, "reset", "--hard", base)
            schema.unlink()
            schema.symlink_to("approved/Requirements.lean")
            with self.assertRaisesRegex(ValueError, "regular Git file"):
                check(root, base, commit())
            git(root, "reset", "--hard", base)
            for directory in APPROVED_ROOTS:
                helper = root / directory / "Helper.lean"
                helper.write_text("-- changed imported semantics\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Helper.lean"):
                    check(root, base, commit())
                git(root, "reset", "--hard", base)
            helper = root / APPROVED_ROOTS[0] / "Helper.lean"
            helper.write_text("-- self-approved change\n", encoding="utf-8")
            baseline = helper.parent / "baseline.json"
            hashes = json.loads(baseline.read_text())
            hashes["approved/Helper.lean"] = hashlib.sha256(helper.read_bytes()).hexdigest()
            baseline.write_text(json.dumps(hashes), encoding="utf-8")
            self_approved = commit()
            with self.assertRaisesRegex(ValueError, "baseline changed"):
                check(root, base, self_approved)
            git(root, "reset", "--hard", base)
            added = helper.parent / "Extra.lean"
            added.write_text("-- extra dependency\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Extra.lean"):
                check(root, base, commit())
            git(root, "reset", "--hard", base)
            helper.unlink()
            with self.assertRaisesRegex(ValueError, "Helper.lean"):
                check(root, base, commit())
            git(root, "reset", "--hard", base)
            helper.unlink()
            helper.symlink_to("Requirements.lean")
            with self.assertRaisesRegex(ValueError, "regular Git file"):
                check(root, base, commit())
            git(root, "reset", "--hard", base)
            malicious = root / "tests/baseline_ci.py"
            malicious.parent.mkdir()
            malicious.write_text("raise RuntimeError('candidate checker executed')\n", encoding="utf-8")
            check(root, base, commit())
            with self.assertRaisesRegex(ValueError, "complete lowercase"):
                check(root, "--help", base)
            with self.assertRaises(subprocess.CalledProcessError):
                check(root, "0" * 40, base)


if __name__ == "__main__":
    unittest.main()
