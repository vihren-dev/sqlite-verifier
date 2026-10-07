"""Select independent public-interface acceptance and adversarial input scenarios."""

from collections.abc import Callable
import json
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.kernel, pytest.mark.requires_lean,
              pytest.mark.requires_native]


@pytest.fixture
def approved(example_factory: Callable[[str], Path]) -> Path:
    """Copy the original approved contract into this case's private directory."""
    return example_factory("approved")


@pytest.fixture
def candidate(example_factory: Callable[[str], Path]) -> Path:
    """Start each candidate attack from the original positive migration."""
    return example_factory("add_column_then_table")


@pytest.fixture
def invoke(runtime_root: Path, approved: Path, candidate: Path,
           command_runner: Callable[..., CommandResult], tmp_path: Path) -> Callable[..., dict[str, object]]:
    """Bind the public entrypoint; callers can substitute only the inputs under test."""
    def verify(expected: str, *, extra: tuple[str, ...] = (), execution_profile: str = "3.51.0",
               replacements: dict[str, Path] | None = None, alternative: Path | None = None,
               contract: Path | None = None) -> dict[str, object]:
        """Check the exact public JSON class and exit status with the existing 90-second deadline."""
        proposed, protected = alternative or candidate, contract or approved
        inputs = {"schema": protected / "schema.sql", "requirements": protected / "Requirements.lean",
                  "interpretation": protected / "Interpretation.lean", "migration": proposed / "migration.sql",
                  "next-interpretation": proposed / "NextInterpretation.lean", "proofs": proposed / "Proofs.lean"}
        inputs.update(replacements or {})
        command = [str(runtime_root / "bin/migration-check"), "verify", "--profile", execution_profile,
                   "--format", "json"]
        for name, path in inputs.items():
            command.extend(["--" + name, str(path)])
        result = command_runner([*command, *extra], cwd=tmp_path, timeout=90)
        report = result.json_object()
        assert report["status"] == expected, result.diagnostic()
        assert result.returncode == (0 if expected == "VERIFIED" else 1), result.diagnostic()
        return report
    return verify


def test_valid_migration_artifacts(invoke: Callable[..., dict[str, object]], tmp_path: Path,
                                  approved: Path) -> None:
    """A valid migration produces exactly the four sealed source/input artifacts."""
    artifacts = tmp_path / "artifacts"
    invoke("VERIFIED", extra=("--artifacts", str(artifacts),
                             "--approved-baseline", str(approved / "baseline.json")))
    assert {path.name for path in artifacts.iterdir()} == {"SchemaInputs.lean", "SqlInputs.lean", "Generated.lean", "inputs.json"}
    assert "def startSchema" in (artifacts / "SchemaInputs.lean").read_text()
    assert "def startSchema" not in (artifacts / "SqlInputs.lean").read_text()
    assert ".addColumn" in (artifacts / "SqlInputs.lean").read_text()
    assert "VerificationConditions" in (artifacts / "Generated.lean").read_text()


@pytest.mark.approval
def test_reverse_migration_reuses_baseline(invoke: Callable[..., dict[str, object]], approved: Path,
                                         example_factory: Callable[[str], Path]) -> None:
    """A different valid statement order verifies against the same checked-in approved baseline."""
    invoke("VERIFIED", alternative=example_factory("table_then_column"),
           extra=("--approved-baseline", str(approved / "baseline.json")))


def test_checked_refutation(invoke: Callable[..., dict[str, object]], example_factory: Callable[[str], Path],
                            approved: Path) -> None:
    """A checked counterargument returns VIOLATED with a nonzero process status."""
    invoke("VIOLATED", alternative=example_factory("missing_required_column"),
           extra=("--approved-baseline", str(approved / "baseline.json")))


def test_allowed_failure(invoke: Callable[..., dict[str, object]], example_factory: Callable[[str], Path]) -> None:
    """An explicitly allowed execution failure satisfies its own approved contract."""
    case = example_factory("allowed_failure")
    invoke("VERIFIED", alternative=case, contract=case / "approved",
           extra=("--approved-baseline", str(case / "approved/baseline.json")))


@pytest.mark.approval
def test_protected_schema_precedes_invalid_proof(invoke: Callable[..., dict[str, object]],
        approved: Path, candidate: Path) -> None:
    """Changed SQL bytes reject before an invalid proof, even when the schema meaning is unchanged."""
    schema = approved / "schema.sql"
    schema.write_bytes(schema.read_bytes() + b"\n-- unapproved schema source change\n")
    (candidate / "Proofs.lean").write_text("import Generated\ndef invalidProof : Nat := false\n")
    report = invoke("INPUT_ERROR", extra=("--approved-baseline", str(approved / "baseline.json")))
    assert "schema.sql" in report["message"], report


def test_application_profile_rejected(invoke: Callable[..., dict[str, object]], tmp_path: Path) -> None:
    """Application/framework metadata cannot masquerade as a SQLite semantic profile."""
    profile = tmp_path / "runner.json"
    profile.write_text(json.dumps({"kind": "sqlite-3.46.0-sqlx-0.9.0-wal-normal-optimize-v1",
                                  "migration": {"version": 20, "description": "new column"}, "previous": []}))
    invoke("INPUT_ERROR", execution_profile=str(profile))


@pytest.mark.parametrize("sql,status", [
    ("-- no statements", "INPUT_ERROR"), ("CREATE TABLE", "INPUT_ERROR"), ("SELECT 1;", "UNSUPPORTED"),
    ("ALTER TABLE invoices ADD other TEXT; CREATE TABLE audit(message TEXT);", "UNVERIFIED"),
], ids=["empty", "malformed", "unsupported_select", "stale_proof"])
def test_invalid_migration(invoke: Callable[..., dict[str, object]], candidate: Path, sql: str, status: str) -> None:
    """Invalid, unsupported and changed migration SQL retain their distinct public outcomes."""
    (candidate / "migration.sql").write_text(sql)
    invoke(status)


def test_unsupported_schema_view(invoke: Callable[..., dict[str, object]], approved: Path) -> None:
    """An unmodeled view in the starting schema returns UNSUPPORTED."""
    schema = approved / "schema.sql"
    schema.write_bytes(schema.read_bytes() + b"\nCREATE VIEW v AS SELECT * FROM invoices;")
    invoke("UNSUPPORTED")


def test_extra_assumption_proof(invoke: Callable[..., dict[str, object]], candidate: Path) -> None:
    """A proof that adds a premise to the required theorem is rejected through the public entrypoint.

    `sorry`, unapproved axioms and forged targets are covered once, directly against the
    checker, in `kernel_gate_test.py`.
    """
    (candidate / "Proofs.lean").write_text(
        "import Generated\ntheorem Proofs.migrationCorrect (extra : False) : Generated.expected := False.elim extra\n")
    invoke("UNVERIFIED")


@pytest.mark.approval
def test_weakened_next_interpretation(invoke: Callable[..., dict[str, object]], candidate: Path) -> None:
    """Removing the protected amount interpretation is rejected independently of other attacks."""
    path = candidate / "NextInterpretation.lean"
    original = path.read_text()
    changed = original.replace('["amount"]', '[]')
    assert changed != original
    path.write_text(changed)
    invoke("UNVERIFIED")


@pytest.fixture
def transitive_contract(approved: Path) -> Path:
    """Add an approved transitive helper to the copied contract."""
    requirements = approved / "Requirements.lean"
    requirements.write_text("import Policy\n" + requirements.read_text())
    (approved / "Policy.lean").write_text("/-- Approved supporting context. -/\ndef policyVersion := 1\n")
    return approved


@pytest.mark.approval
def test_approved_transitive_dependency(invoke: Callable[..., dict[str, object]], transitive_contract: Path,
                                      tmp_path: Path) -> None:
    """A valid approved helper is admitted and recorded in the generated input artifacts."""
    report = invoke("VERIFIED", contract=transitive_contract, extra=("--artifacts", str(tmp_path / "artifacts")))
    assert "approved/Policy.lean" in report["inputs"]
    assert json.loads((tmp_path / "artifacts/inputs.json").read_text()) == report["inputs"]


def test_caller_model_namespace_remains_untrusted(invoke: Callable[..., dict[str, object]],
                                                 candidate: Path) -> None:
    """A caller-owned model namespace resolves and is replayed without becoming a protected module."""
    helper = candidate / 'Belay/Sqlite/Caller.lean'
    helper.parent.mkdir(parents=True)
    helper.write_text('def Belay.Sqlite.callerValue : Nat := 7\n')
    proof = candidate / 'Proofs.lean'
    proof.write_text(proof.read_text().replace('import Generated', 'import Generated\nimport Belay.Sqlite.Caller')
        .replace('  SqliteVerifier.Demonstration.migrationCorrect',
                 '  by\n    have checked : Belay.Sqlite.callerValue = 7 := rfl\n    exact SqliteVerifier.Demonstration.migrationCorrect'))
    invoke('VERIFIED')
