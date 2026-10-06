"""Select kernel replay attacks independently against private compiled fixture copies."""

import pytest

from tests.kernel_attack_cases import PROOF_ATTACKS
from tests.kernel_fixture import KernelCase, compiled_kernel, kernel, source

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean]


def test_missing_sysroot(kernel: KernelCase) -> None:
    """The checker requires an explicit pinned Lean installation even when imports exist."""
    environment = dict(kernel.environment)
    environment.pop("LEAN_SYSROOT")
    result = kernel.check(environment=environment)
    assert result.returncode != 0 and "LEAN_SYSROOT" in result.stderr, result.diagnostic()


def test_relative_library_path(kernel: KernelCase) -> None:
    """A relative library path cannot redirect the checker's trusted imports."""
    result = kernel.check(library=".")
    assert result.returncode != 0 and "absolute existing directory" in result.stderr, result.diagnostic()


@pytest.mark.parametrize("text,diagnostic,accepted", PROOF_ATTACKS)
def test_proof_attack(kernel: KernelCase, text: str, diagnostic: str, accepted: bool) -> None:
    """Replay honest proofs without initializers and reject forged bodies, axioms and protected substitutions."""
    kernel.compile("candidate", "Proofs", text.replace("{valid}", source("Proofs")))
    result = kernel.check()
    assert (result.returncode == 0) == accepted, result.diagnostic()
    assert diagnostic in result.stderr, result.diagnostic()
    if text.startswith("import Lean\ndef "):
        assert "already contains" in result.stderr or "modified protected" in result.stderr, result.diagnostic()


@pytest.mark.approval
def test_approved_source_substitutes_schema(kernel: KernelCase) -> None:
    """Even approved logical source cannot replace the generated starting schema declaration."""
    kernel.compile("trusted", "Requirements", source("Requirements") + "\ndef Generated.startSchema : Nat := 0\n")
    result = kernel.check()
    assert result.returncode == 1 and "Generated.startSchema" in result.stderr, result.diagnostic()
    assert "already contains" in result.stderr or "modified protected" in result.stderr, result.diagnostic()


def test_forged_convenience_target(kernel: KernelCase) -> None:
    """A trivial convenience alias cannot replace the independently reconstructed target."""
    kernel.compile("candidate", "Generated", "import SqlInputs\nimport NextInterpretation\ndef Generated.expected : Prop := True")
    kernel.compile("candidate", "Proofs", "import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := trivial")
    result = kernel.check()
    assert result.returncode != 0 and "reconstructed" in result.stderr, result.diagnostic()


def test_changed_sealed_profile(kernel: KernelCase) -> None:
    """A candidate target cannot silently substitute another sealed SQLite version."""
    kernel.compile("trusted", "SqlInputs", source("SqlInputs").replace(".sqlite351", ".sqlite346"))
    legacy = source("Generated").replace("NextInterpretation.failures profile", "NextInterpretation.failures")
    kernel.compile("candidate", "Generated", legacy)
    kernel.compile("candidate", "Proofs", source("Proofs"))
    result = kernel.check()
    assert result.returncode == 1 and "reconstructed" in result.stderr, result.diagnostic()


@pytest.fixture
def negative_kernel(kernel: KernelCase) -> KernelCase:
    """Prepare a false admitted interpretation independently for either refutation case."""
    kernel.compile("trusted", "Interpretation", source("Interpretation").replace("Prop := True", "Prop := False"))
    for module in ("NextInterpretation", "Generated"):
        kernel.compile("candidate", module, source(module))
    return kernel


def test_checked_refutation(negative_kernel: KernelCase) -> None:
    """A kernel-checked negative argument gets the distinct refutation exit code."""
    negative_kernel.compile("candidate", "Proofs", "import Generated\ntheorem Proofs.migrationViolated : ¬ Generated.expected := by\n"
                            "  intro correct\n  obtain ⟨database, admitted⟩ := correct.nonempty\n  exact admitted.2\n")
    result = negative_kernel.check()
    assert result.returncode == 2, result.diagnostic()


def test_unfinished_refutation(negative_kernel: KernelCase) -> None:
    """An unfinished negative argument is unverified and identifies the unapproved sorry axiom."""
    negative_kernel.compile("candidate", "Proofs", "import Generated\ntheorem Proofs.migrationViolated : ¬ Generated.expected := by sorry")
    result = negative_kernel.check()
    assert result.returncode == 1 and "sorryAx" in result.stderr, result.diagnostic()
