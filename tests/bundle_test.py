"""ADR 0003 data path through the public entrypoint: `prepare` then `verify-bundle`."""

from collections.abc import Callable
import hashlib
import json
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult
from tests.proof_exporter_test import exporter_runtime_identity, input_digests

pytestmark = [pytest.mark.e2e, pytest.mark.kernel, pytest.mark.requires_lean, pytest.mark.requires_native]
APPLICATION_KEY_HEADER = {"bundle": 1, "trusted_imports": ["Init", "SqliteVerifier.ApplicationKeyDemonstration"]}
"""The authored variant imports the complete application-key certificate from the selected library."""


@pytest.fixture
def data_path(runtime_root: Path, tmp_path: Path,
              command_runner: Callable[..., CommandResult]) -> Callable[..., dict[str, object]]:
    """Prepare a bundle from one contract/candidate pair, then verify it against another contract."""
    def run(*, approved: Path, candidate: Path, schema: Path, profile: str = "3.51.0",
            checked_approved: Path | None = None, checked_migration: Path | None = None,
            directory: Path | None = None) -> dict[str, object]:
        """Return verify-bundle's JSON report after asserting prepare succeeded."""
        def common(contract: Path, migration: Path) -> list[str]:
            return ["--profile", profile, "--format", "json", "--schema", str(schema),
                    "--requirements", str(contract / "Requirements.lean"),
                    "--interpretation", str(contract / "Interpretation.lean"), "--migration", str(migration)]
        selected = directory or tmp_path
        selected.mkdir(exist_ok=True)
        bundle = selected / "proof.bundle"
        launcher = str(runtime_root / "bin/migration-check")
        prepared = command_runner([launcher, "prepare", *common(approved, candidate / "migration.sql"),
                                   "--next-interpretation", str(candidate / "NextInterpretation.lean"),
                                   "--proofs", str(candidate / "Proofs.lean"),
                                   "--workspace", str(selected / "agent"), "--output", str(bundle)],
                                  cwd=tmp_path, timeout=180)
        assert prepared.returncode == 0 and prepared.json_object()["status"] == "PREPARED", prepared.diagnostic()
        checked = command_runner([launcher, "verify-bundle",
                                  *common(checked_approved or approved, checked_migration or candidate / "migration.sql"),
                                  "--bundle", str(bundle)], cwd=tmp_path, timeout=120)
        report = checked.json_object()
        assert checked.returncode == (0 if report["status"] == "VERIFIED" else 1), checked.diagnostic()
        return report
    return run


def test_allowed_failure_through_data_path(data_path: Callable[..., dict[str, object]],
                                          example_factory: Callable[[str], Path]) -> None:
    """The allowed-failure example is VERIFIED through `prepare` and `verify-bundle`.

    The other shipped examples go through the data path in `test_current_native_export` and
    `test_application_key_bundle_repeatability`, which also check their status.
    """
    examples = example_factory("allowed_failure")
    report = data_path(approved=examples / "approved", candidate=examples,
                       schema=examples / "approved/schema.sql")
    assert report["status"] == "VERIFIED", report


def test_application_key_bundle_repeatability(data_path: Callable[..., dict[str, object]],
        example_factory: Callable[[str], Path], tmp_path: Path, runtime_root: Path,
        exporter_runtime_identity: dict[str, object], record_testsuite_property: Callable[[str, object], None]) -> None:
    """Independent preparation binds identical keyed certificates to the selected inputs and library."""
    examples = example_factory("application_keys")
    options = {"approved": examples / "approved", "candidate": examples / "add_column_then_table",
               "schema": examples / "approved/schema.sql"}
    hashes = input_digests(examples, "approved", "add_column_then_table", "approved/schema.sql")
    assert hashes == input_digests(runtime_root / "examples/application_keys", "approved",
                                  "add_column_then_table", "approved/schema.sql")
    reports = [data_path(**options, directory=tmp_path / label) for label in ("first", "second")]
    payloads = [(tmp_path / label / "proof.bundle").read_bytes() for label in ("first", "second")]
    for report, payload in zip(reports, payloads, strict=True):
        assert report["status"] == "VERIFIED" and json.loads(payload.splitlines()[0]) == APPLICATION_KEY_HEADER
        expected = {"profile": "3.51.0", "schema.sql": hashes["approved/schema.sql"],
            "migration.sql": hashes["add_column_then_table/migration.sql"], "bundle": hashlib.sha256(payload).hexdigest(),
            **{name: digest for name, digest in hashes.items() if name.startswith("approved/") and name.endswith(".lean")}}
        assert isinstance(report["inputs"], dict) and expected.items() <= report["inputs"].items(), report
    assert payloads[0] == payloads[1]
    record_testsuite_property("application-key-example", json.dumps({"inputSha256": hashes,
        "runtime": exporter_runtime_identity, "header": APPLICATION_KEY_HEADER,
        "bundleSha256": hashlib.sha256(payloads[0]).hexdigest(), "checks": reports}, sort_keys=True))


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


def test_sql_edit_reuses_modules_without_sql_inputs(runtime_root: Path, example_factory: Callable[[str], Path],
                                                     tmp_path: Path, command_runner: Callable[..., CommandResult]) -> None:
    """After an Atuin SQL edit, modules that do not import SqlInputs are reused and the bundle verifies."""
    atuin = example_factory("atuin")
    launcher = str(runtime_root / "bin/migration-check")
    common = ["--profile", "3.46.0", "--format", "json", "--schema", str(atuin / "schema.sql"),
              "--requirements", str(atuin / "approved/Requirements.lean"),
              "--interpretation", str(atuin / "approved/Interpretation.lean"),
              "--migration", str(atuin / "migration.sql")]
    candidate = ["--next-interpretation", str(atuin / "NextInterpretation.lean"), "--proofs", str(atuin / "Proofs.lean")]
    bundle = tmp_path / "atuin.bundle"

    def prepare() -> dict[str, object]:
        """Prepare into the same persistent agent workspace."""
        result = command_runner([launcher, "prepare", *common, *candidate, "--workspace", str(tmp_path / "agent"),
                                 "--output", str(bundle)], cwd=tmp_path, timeout=180)
        report = result.json_object()
        assert report["status"] == "PREPARED", result.diagnostic()
        return report

    first = prepare()
    for path, old, new in ((atuin / "migration.sql", "add column shell text;", "add column other text;"),
                           (atuin / "AtuinFacts.lean", 'name := "shell"', 'name := "other"')):
        text = path.read_text()
        assert old in text
        path.write_text(text.replace(old, new))
    second = prepare()
    assert second["reused_modules"] == 2 and second["compiled_modules"] == first["compiled_modules"] - 2, second
    checked = command_runner([launcher, "verify-bundle", *common, "--bundle", str(bundle)], cwd=tmp_path, timeout=120)
    assert checked.json_object()["status"] == "VERIFIED", checked.diagnostic()
