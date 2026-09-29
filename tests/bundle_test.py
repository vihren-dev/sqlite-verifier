"""ADR 0003 data path through the public entrypoint: `prepare` then `verify-bundle`."""

from collections.abc import Callable
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.kernel, pytest.mark.requires_lean, pytest.mark.requires_native]


@pytest.fixture
def data_path(runtime_root: Path, tmp_path: Path,
              command_runner: Callable[..., CommandResult]) -> Callable[..., dict[str, object]]:
    """Prepare a bundle from one contract/candidate pair, then verify it against another contract."""
    def run(*, approved: Path, candidate: Path, schema: Path, profile: str = "3.51.0",
            checked_approved: Path | None = None, checked_migration: Path | None = None) -> dict[str, object]:
        """Return verify-bundle's JSON report after asserting prepare succeeded."""
        def common(contract: Path, migration: Path) -> list[str]:
            return ["--profile", profile, "--format", "json", "--schema", str(schema),
                    "--requirements", str(contract / "Requirements.lean"),
                    "--interpretation", str(contract / "Interpretation.lean"), "--migration", str(migration)]
        bundle = tmp_path / "proof.bundle"
        launcher = str(runtime_root / "bin/migration-check")
        prepared = command_runner([launcher, "prepare", *common(approved, candidate / "migration.sql"),
                                   "--next-interpretation", str(candidate / "NextInterpretation.lean"),
                                   "--proofs", str(candidate / "Proofs.lean"),
                                   "--workspace", str(tmp_path / "agent"), "--output", str(bundle)],
                                  cwd=tmp_path, timeout=180)
        assert prepared.json_object()["status"] == "PREPARED", prepared.diagnostic()
        checked = command_runner([launcher, "verify-bundle",
                                  *common(checked_approved or approved, checked_migration or candidate / "migration.sql"),
                                  "--bundle", str(bundle)], cwd=tmp_path, timeout=120)
        report = checked.json_object()
        assert checked.returncode == (0 if report["status"] == "VERIFIED" else 1), checked.diagnostic()
        return report
    return run


@pytest.mark.parametrize("approved,candidate,schema,profile,status", [
    ("approved", "add_column_then_table", "approved/schema.sql", "3.51.0", "VERIFIED"),
    ("approved", "missing_required_column", "approved/schema.sql", "3.51.0", "VIOLATED"),
    ("allowed_failure/approved", "allowed_failure", "allowed_failure/approved/schema.sql", "3.51.0", "VERIFIED"),
    ("atuin/approved", "atuin", "atuin/schema.sql", "3.46.0", "VERIFIED"),
], ids=["positive", "refutation", "allowed_failure", "atuin"])
def test_status_parity(data_path: Callable[..., dict[str, object]], example_factory: Callable[[str], Path],
                       approved: str, candidate: str, schema: str, profile: str, status: str) -> None:
    """Each shipped example gets the same status through the data path as through `verify`."""
    examples = example_factory(".")
    report = data_path(approved=examples / approved, candidate=examples / candidate,
                       schema=examples / schema, profile=profile)
    assert report["status"] == status, report


@pytest.fixture
def small(example_factory: Callable[[str], Path]) -> dict[str, Path]:
    """Private copies of the small approved contract and positive candidate."""
    examples = example_factory(".")
    return {"approved": examples / "approved", "candidate": examples / "add_column_then_table",
            "schema": examples / "approved/schema.sql", "reverse": examples / "table_then_column"}


@pytest.mark.parametrize("proof,diagnostic", [
    ("theorem Proofs.migrationCorrect : Generated.expected := by sorry", "sorryAx"),
    ("axiom unapproved : Generated.expected\ntheorem Proofs.migrationCorrect : Generated.expected := unapproved",
     "unapproved axiom"),
    ("theorem Proofs.migrationCorrect : True := trivial", "reconstructed verification target"),
], ids=["sorry", "forbidden_axiom", "wrong_target"])
def test_invalid_proof_rejected(data_path: Callable[..., dict[str, object]], small: dict[str, Path],
                                proof: str, diagnostic: str) -> None:
    """Unfinished proofs, extra axioms and proofs of another statement are UNVERIFIED."""
    (small["candidate"] / "Proofs.lean").write_text("import Generated\n" + proof + "\n")
    report = data_path(approved=small["approved"], candidate=small["candidate"], schema=small["schema"])
    assert report["status"] == "UNVERIFIED" and diagnostic in str(report["message"]), report


def test_bundle_from_altered_contract_rejected(data_path: Callable[..., dict[str, object]],
                                                small: dict[str, Path], tmp_path: Path) -> None:
    """A bundle built against an altered copy of the contract cannot replace the approved one."""
    altered = tmp_path / "altered"
    altered.mkdir()
    for name in ("Requirements.lean", "Interpretation.lean"):
        (altered / name).write_bytes((small["approved"] / name).read_bytes())
    requirements = altered / "Requirements.lean"
    # Definitionally equal, so the candidate still compiles, but a different declaration record.
    changed = requirements.read_text().replace("valid := fun _ => True",
                                               "valid := fun _ => (fun (claim : Prop) => claim) True")
    assert changed != requirements.read_text()
    requirements.write_text(changed)
    report = data_path(approved=altered, candidate=small["candidate"], schema=small["schema"],
                       checked_approved=small["approved"])
    assert report["status"] == "UNVERIFIED" and "modified protected declaration" in str(report["message"]), report


def test_bundle_bound_to_prepared_sql(data_path: Callable[..., dict[str, object]], small: dict[str, Path]) -> None:
    """A bundle prepared for one migration cannot verify a different migration's SQL."""
    report = data_path(approved=small["approved"], candidate=small["candidate"], schema=small["schema"],
                       checked_migration=small["reverse"] / "migration.sql")
    assert report["status"] == "UNVERIFIED" and "modified protected declaration" in str(report["message"]), report


def test_shared_interpretation_file(data_path: Callable[..., dict[str, object]], small: dict[str, Path],
                                    tmp_path: Path) -> None:
    """One file may supply both the current and next interpretation, as `verify` accepts."""
    shared = tmp_path / "shared"
    shared.mkdir()
    (shared / "Requirements.lean").write_bytes((small["approved"] / "Requirements.lean").read_bytes())
    current = (small["approved"] / "Interpretation.lean").read_text().replace(
        "import Requirements\n", "import Requirements\nimport SqliteVerifier.Demonstration\n")
    (shared / "Interpretation.lean").write_text(current + """
namespace NextInterpretation
def next : SqliteVerifier.Interpretation Requirements.LogicalState := SqliteVerifier.Demonstration.next
def failures : SqliteVerifier.FailureRepresentation Requirements.LogicalState := SqliteVerifier.unreachableFailures
end NextInterpretation
""")
    candidate = tmp_path / "candidate"
    candidate.mkdir()
    (candidate / "migration.sql").write_bytes((small["candidate"] / "migration.sql").read_bytes())
    (candidate / "Proofs.lean").write_bytes((small["candidate"] / "Proofs.lean").read_bytes())
    (candidate / "NextInterpretation.lean").symlink_to(shared / "Interpretation.lean")
    report = data_path(approved=shared, candidate=candidate, schema=small["schema"])
    assert report["status"] == "VERIFIED", report
