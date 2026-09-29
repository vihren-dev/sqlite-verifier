"""Exercise target-owned baseline checks against adversarial candidate Git objects."""

import hashlib
import json
from pathlib import Path
import subprocess

import pytest

from tests.baseline_ci import APPROVED_ROOTS, SCHEMA_PATHS, check, git

pytestmark = [pytest.mark.integration, pytest.mark.approval, pytest.mark.requires_native("git")]


def test_source_and_manifest_drift(tmp_path: Path) -> None:
    """Pin complete source sets, including transitive helpers, in the target branch."""
    root = tmp_path
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
        with pytest.raises(ValueError, match="schema.sql"):
            check(root, base, commit())
        git(root, "reset", "--hard", base)
    schema.unlink()
    schema.symlink_to("approved/Requirements.lean")
    with pytest.raises(ValueError, match="regular Git file"):
        check(root, base, commit())
    git(root, "reset", "--hard", base)
    for directory in APPROVED_ROOTS:
        helper = root / directory / "Helper.lean"
        helper.write_text("-- changed imported semantics\n", encoding="utf-8")
        with pytest.raises(ValueError, match="Helper.lean"):
            check(root, base, commit())
        git(root, "reset", "--hard", base)
    helper = root / APPROVED_ROOTS[0] / "Helper.lean"
    helper.write_text("-- self-approved change\n", encoding="utf-8")
    baseline = helper.parent / "baseline.json"
    hashes = json.loads(baseline.read_text())
    hashes["approved/Helper.lean"] = hashlib.sha256(helper.read_bytes()).hexdigest()
    baseline.write_text(json.dumps(hashes), encoding="utf-8")
    self_approved = commit()
    with pytest.raises(ValueError, match="baseline changed"):
        check(root, base, self_approved)
    git(root, "reset", "--hard", base)
    added = helper.parent / "Extra.lean"
    added.write_text("-- extra dependency\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Extra.lean"):
        check(root, base, commit())
    git(root, "reset", "--hard", base)
    helper.unlink()
    with pytest.raises(ValueError, match="Helper.lean"):
        check(root, base, commit())
    git(root, "reset", "--hard", base)
    helper.unlink()
    helper.symlink_to("Requirements.lean")
    with pytest.raises(ValueError, match="regular Git file"):
        check(root, base, commit())
    git(root, "reset", "--hard", base)
    malicious = root / "tests/baseline_ci.py"
    malicious.parent.mkdir()
    malicious.write_text("raise RuntimeError('candidate checker executed')\n", encoding="utf-8")
    check(root, base, commit())
    with pytest.raises(ValueError, match="complete lowercase"):
        check(root, "--help", base)
    with pytest.raises(subprocess.CalledProcessError):
        check(root, "0" * 40, base)
