"""Each old kernel attack reaches the bundle checker independently of preparation acceptance."""

import json
from pathlib import Path

import pytest

from tests.bundle_attack_fixture import BundleCase, bundle_case
from tests.bundle_hostile_records import HostileBundle
from tests.kernel_attack_cases import PROOF_ATTACKS
from tests.kernel_fixture import KernelCase, compiled_kernel, kernel, source

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean]


def test_missing_sysroot(bundle_case: BundleCase) -> None:
    """The data checker requires the same explicit pinned toolchain as the old gate."""
    environment = dict(bundle_case.kernel.environment)
    environment.pop("LEAN_SYSROOT")
    result = bundle_case.check(bundle_case.export(), environment=environment)
    assert result.returncode == 1 and "LEAN_SYSROOT" in result.stderr, result.diagnostic()


def test_relative_library_path(bundle_case: BundleCase) -> None:
    """Header imports cannot redirect protected library resolution through the working directory."""
    result = bundle_case.check(bundle_case.export(), library=".")
    assert result.returncode == 1 and "absolute existing directory" in result.stderr, result.diagnostic()


@pytest.mark.parametrize("text,diagnostic,accepted", PROOF_ATTACKS)
def test_proof_attack(bundle_case: BundleCase, text: str, diagnostic: str, accepted: bool) -> None:
    """Handwritten data covers compiler/export omissions; remaining attacks use actual candidate exports."""
    if text.startswith("import Lean\ndef "):
        raw = HostileBundle(bundle_case.export())
        raw.protected(diagnostic)
        bundle = raw.write(bundle_case.kernel.root / "hostile.ndjson")
    elif "debug.skipKernelTC" in text:
        raw = HostileBundle(bundle_case.export())
        raw.forged_body()
        bundle = raw.write(bundle_case.kernel.root / "hostile.ndjson")
    elif "unsafe def" in text or "safety := .partial" in text:
        raw = HostileBundle(bundle_case.export())
        raw.unsafe_or_partial("unsafe" if "unsafe def" in text else "partial")
        bundle = raw.write(bundle_case.kernel.root / "hostile.ndjson")
    else:
        bundle_case.kernel.compile("candidate", "Proofs", text.replace("{valid}", source("Proofs")))
        bundle = bundle_case.export()
    result = bundle_case.check(bundle)
    assert result.returncode == (0 if accepted else 1), result.diagnostic()
    # The new boundary rejects a protected substitution before comparing its theorem target.
    expected = "modified protected" if text.startswith("import Lean\ndef ") else diagnostic
    assert expected in result.stderr, result.diagnostic()


@pytest.mark.approval
def test_approved_source_substitutes_schema(bundle_case: BundleCase) -> None:
    """Approved logical source still cannot replace the generated starting schema."""
    bundle = bundle_case.export()
    case = bundle_case.kernel
    case.compile("trusted", "Requirements", source("Requirements") + "\ndef Generated.startSchema : Nat := 0\n")
    result = bundle_case.check(bundle)
    assert result.returncode == 1 and "Generated.startSchema" in result.stderr, result.diagnostic()


def test_forged_convenience_target(bundle_case: BundleCase) -> None:
    """A candidate alias for True cannot replace the independently reconstructed verification target."""
    case = bundle_case.kernel
    case.compile("candidate", "Generated", "import SqlInputs\nimport NextInterpretation\ndef Generated.expected : Prop := True")
    case.compile("candidate", "Proofs", "import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := trivial")
    result = bundle_case.check(bundle_case.export())
    assert result.returncode == 1 and "reconstructed" in result.stderr, result.diagnostic()


def test_changed_sealed_profile(bundle_case: BundleCase) -> None:
    """A changed exported profile is rejected where the checker constructs its own sealed input."""
    raw = HostileBundle(bundle_case.export())
    raw.changed_profile()
    result = bundle_case.check(raw.write(bundle_case.kernel.root / "other-profile.ndjson"))
    assert result.returncode == 1 and "Generated.profile" in result.stderr, result.diagnostic()


@pytest.mark.parametrize("unfinished", [False, True], ids=["checked_refutation", "unfinished_refutation"])
def test_refutation(bundle_case: BundleCase, unfinished: bool) -> None:
    """Direct data checking preserves exit 2 for a checked negative proof and rejects sorry."""
    case = bundle_case.kernel
    case.compile("trusted", "Interpretation", source("Interpretation").replace("Prop := True", "Prop := False"))
    for module in ("NextInterpretation", "Generated"):
        case.compile("candidate", module, source(module))
    proof = ("sorry" if unfinished else "\n  intro correct\n  obtain ⟨database, admitted⟩ := correct.nonempty\n  exact admitted.2\n")
    case.compile("candidate", "Proofs", "import Generated\ntheorem Proofs.migrationViolated : ¬ Generated.expected := by " + proof)
    result = bundle_case.check(bundle_case.export())
    assert result.returncode == (1 if unfinished else 2), result.diagnostic()
    if unfinished:
        assert "sorryAx" in result.stderr, result.diagnostic()


@pytest.mark.parametrize("header,diagnostic", [
    ({"trusted_imports": []}, "unsupported bundle format"),
    ({"bundle": 2, "trusted_imports": []}, "unsupported bundle format"),
    ({"bundle": 1, "trusted_imports": "Proofs"}, "bundle checker rejected"),
    ({"bundle": 1, "trusted_imports": ["Proofs"]}, "Proofs"),
], ids=["missing_version", "other_version", "wrong_import_type", "candidate_as_trusted_import"])
def test_hostile_header(bundle_case: BundleCase, header: dict[str, object], diagnostic: str) -> None:
    """A header cannot import candidate modules from their private source directory."""
    bundle = bundle_case.export()
    lines = bundle.read_text().splitlines()
    bundle.write_text(json.dumps(header) + "\n" + "\n".join(lines[1:]) + "\n")
    result = bundle_case.check(bundle)
    assert result.returncode == 1 and diagnostic in result.stderr, result.diagnostic()
