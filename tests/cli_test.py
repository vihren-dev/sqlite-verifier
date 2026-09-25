"""Run the seven-input product interface against real reusable proof examples."""

import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "examples"
COMMAND = ROOT / "bin/migration-check"


def invoke(candidate: Path, approved: Path, expected: str, *, extra: tuple[str, ...] = (),
           execution_profile: str = "3.51.0",
           replacements: dict[str, Path] | None = None) -> dict[str, object]:
    """Assert both process exit and public JSON class under a bounded complete verification."""
    inputs = {"schema": approved / "schema.sql", "requirements": approved / "Requirements.lean",
              "interpretation": approved / "Interpretation.lean", "migration": candidate / "migration.sql",
              "next-interpretation": candidate / "NextInterpretation.lean", "proofs": candidate / "Proofs.lean"}
    inputs.update(replacements or {})
    command = [str(COMMAND), "verify", "--profile", execution_profile, "--format", "json"]
    for name, path in inputs.items():
        command.extend(["--" + name, str(path)])
    result = subprocess.run([*command, *extra], cwd=ROOT, env=os.environ.copy(),
                            text=True, capture_output=True, timeout=90)
    report: dict[str, object] = json.loads(result.stdout)
    assert report["status"] == expected, (command, report, result.stderr)
    assert result.returncode == (0 if expected == "VERIFIED" else 1), result
    return report


def main() -> None:
    """Exercise real proof acceptance, checked refutation, input attacks, and protected imports."""
    approved = EXAMPLES / "approved"
    candidate = EXAMPLES / "add_column_then_table"
    with TemporaryDirectory(prefix="verifier-e2e-") as temporary:
        work = Path(temporary)
        artifacts = work / "artifacts"
        invoke(candidate, approved, "VERIFIED", extra=("--artifacts", str(artifacts)))
        assert {path.name for path in artifacts.iterdir()} == {"SqlInputs.lean", "Generated.lean", "inputs.json"}
        assert ".addColumn" in (artifacts / "SqlInputs.lean").read_text()
        assert "VerificationConditions" in (artifacts / "Generated.lean").read_text()
        baseline = artifacts / "inputs.json"
        invoke(EXAMPLES / "table_then_column", approved, "VERIFIED",
               extra=("--approved-baseline", str(baseline)))
        invoke(EXAMPLES / "missing_required_column", approved, "VIOLATED")
        invoke(EXAMPLES / "allowed_failure", EXAMPLES / "allowed_failure/approved", "VERIFIED")
        changed_profile = work / "runner.json"
        changed_profile.write_text(json.dumps({
            "kind": "sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1",
            "migration": {"version": 20, "description": "new column"}, "previous": []}))
        invoke(candidate, approved, "UNSUPPORTED", execution_profile=str(changed_profile))
        no_transaction = work / "no-transaction.sql"
        no_transaction.write_bytes(b"-- no-transaction\nALTER TABLE invoices ADD note TEXT;\n")
        invoke(candidate, approved, "UNSUPPORTED", execution_profile=str(changed_profile),
               replacements={"migration": no_transaction})

        modified = work / "candidate"
        shutil.copytree(candidate, modified)
        migration = modified / "migration.sql"
        for sql, status in [("-- no statements", "INPUT_ERROR"), ("CREATE TABLE", "INPUT_ERROR"),
                            ("SELECT 1;", "UNSUPPORTED"),
                            ("ALTER TABLE invoices ADD other TEXT; CREATE TABLE audit(message TEXT);", "UNVERIFIED")]:
            migration.write_text(sql)
            invoke(modified, approved, status)
        migration.write_bytes((candidate / "migration.sql").read_bytes())
        bad_schema = work / "schema.sql"
        bad_schema.write_bytes((approved / "schema.sql").read_bytes() + b"\nCREATE VIEW v AS SELECT * FROM invoices;")
        invoke(candidate, approved, "UNSUPPORTED", replacements={"schema": bad_schema})

        proof = modified / "Proofs.lean"
        for source in [
            "import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := by sorry\n",
            "import Generated\ntheorem Proofs.migrationCorrect (extra : False) : Generated.expected := False.elim extra\n",
            "import Generated\naxiom unapproved : Generated.expected\ntheorem Proofs.migrationCorrect : Generated.expected := unapproved\n",
        ]:
            proof.write_text(source)
            invoke(modified, approved, "UNVERIFIED")
        (modified / "Generated.lean").write_text("def Generated.expected : Prop := True\n")
        proof.write_text("import Generated\ntheorem Proofs.migrationCorrect : True := trivial\n")
        invoke(modified, approved, "UNVERIFIED")
        proof.write_bytes((candidate / "Proofs.lean").read_bytes())
        next_file = modified / "NextInterpretation.lean"
        next_file.write_text((candidate / "NextInterpretation.lean").read_text().replace('["amount"]', '[]'))
        invoke(modified, approved, "UNVERIFIED")

        protected = work / "approved"
        shutil.copytree(approved, protected)
        requirements = protected / "Requirements.lean"
        requirements.write_text("import Policy\n" + requirements.read_text())
        helper = protected / "Policy.lean"
        helper.write_text("/-- Approved supporting context. -/\ndef policyVersion := 1\n")
        approved_artifacts = work / "approved-artifacts"
        invoke(candidate, protected, "VERIFIED", extra=("--artifacts", str(approved_artifacts)))
        helper.write_text("/-- A proposed change still requires human review. -/\ndef policyVersion := 2\n")
        report = invoke(candidate, protected, "INPUT_ERROR",
                        extra=("--approved-baseline", str(approved_artifacts / "inputs.json")))
        assert "approved/Policy.lean" in str(report["message"])
    print("CLI: reusable positive, refuted, allowed-failure and adversarial input/dependency cases passed")


if __name__ == "__main__":
    main()
