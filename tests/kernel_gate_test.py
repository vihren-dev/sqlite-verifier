"""Select kernel replay attacks independently against private compiled fixture copies."""

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
import os
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult, copy_mutable_tree, run_command

FIXTURES = Path(__file__).with_name("kernel_gate")
pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean]


def source(module: str) -> str:
    """Read harmless checked-in source only when an executing case needs it."""
    return (FIXTURES / f"{module}.lean").read_text()


@dataclass
class KernelCase:
    """Keep compiler and checker commands bound to one mutable trusted/candidate pair."""

    root: Path
    library: Path
    sysroot: Path
    checker: Path
    environment: dict[str, str]
    runner: Callable[..., CommandResult]

    def compile(self, side: str, module: str, text: str) -> None:
        """Compile one deliberate fixture mutation with the existing 30-second deadline."""
        directory = self.root / side
        (directory / f"{module}.lean").write_text(text)
        result = self.runner([str(self.sysroot / "bin/lean"), "-o", f"{module}.olean", f"{module}.lean"],
                             cwd=directory, environment=self.environment, timeout=30)
        assert result.returncode == 0, result.diagnostic()

    def check(self, *, environment: dict[str, str] | None = None, library: str | None = None) -> CommandResult:
        """Replay the private artifacts; the test deadline does not change production limits."""
        result = self.runner([str(self.checker), library or str(self.library), str(self.root / "trusted"),
                              str(self.root / "candidate")], cwd=self.root, timeout=60,
                             environment=self.environment if environment is None else environment)
        assert "CANDIDATE_INITIALIZER_RAN" not in result.stdout + result.stderr, result.diagnostic()
        return result


def context(root: Path, library: Path, sysroot: Path, checker: Path,
            environment: dict[str, str], runner: Callable[..., CommandResult]) -> KernelCase:
    """Replace inherited import paths with this case's explicit trusted toolchain and trees."""
    environment = {**environment, "LEAN_SYSROOT": str(sysroot),
                   "LEAN_PATH": os.pathsep.join(map(str, (library, root / "trusted", root / "candidate")))}
    return KernelCase(root, library, sysroot, checker, environment, runner)


@pytest.fixture(scope="session")
def compiled_kernel(tmp_path_factory: pytest.TempPathFactory, lean_library: Path,
                    lean_sysroot: Path, proof_checker: Path) -> Path:
    """Compile common fixtures once; cases receive writable copies and never mutate this tree."""
    root = tmp_path_factory.mktemp("kernel-common")
    (root / "trusted").mkdir()
    (root / "candidate").mkdir()

    def compile_runner(arguments: Sequence[str], *, cwd: Path,
                       environment: Mapping[str, str], timeout: float) -> CommandResult:
        """Retain common fixture setup commands if compilation fails before a case can run."""
        return run_command(arguments, cwd=cwd, environment=environment, timeout=timeout,
                           artifacts=root / "commands")

    common = context(root, lean_library, lean_sysroot, proof_checker, dict(os.environ), compile_runner)
    for module in ("SchemaInputs", "Requirements", "Interpretation", "SqlInputs"):
        common.compile("trusted", module, source(module))
    for module in ("NextInterpretation", "Generated", "Proofs"):
        common.compile("candidate", module, source(module))
    return root


@pytest.fixture
def kernel(compiled_kernel: Path, tmp_path: Path, lean_library: Path, lean_sysroot: Path,
           proof_checker: Path, runtime_environment: dict[str, str],
           command_runner: Callable[..., CommandResult]) -> KernelCase:
    """Give each attack its own compiled sources and artifacts, independent of selection order."""
    root = tmp_path / "kernel"
    copy_mutable_tree(compiled_kernel, root)
    return context(root, lean_library, lean_sysroot, proof_checker, runtime_environment, command_runner)


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


@pytest.mark.parametrize("text,diagnostic,accepted", [
    pytest.param("{valid}", "", True, id="valid"),
    pytest.param('{valid}\ninitialize IO.eprintln "CANDIDATE_INITIALIZER_RAN"\n', "", True, id="initializer_ignored"),
    pytest.param("import Lean\nimport Generated\nset_option debug.skipKernelTC true in\n"
                 "run_elab Lean.addDecl (.thmDecl { name := `Proofs.migrationCorrect, levelParams := [], "
                 "type := Lean.mkConst `Generated.expected, value := Lean.mkConst `True.intro })",
                 "while replaying", False, id="forged_kernel_body"),
    pytest.param("import Generated\ntheorem Proofs.migrationCorrect : True := trivial", "reconstructed", False, id="wrong_theorem"),
    pytest.param("import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := by sorry", "sorryAx", False, id="sorry"),
    pytest.param("import Generated\naxiom forbidden : Generated.expected\ndef helper := forbidden\n"
                 "theorem Proofs.migrationCorrect : Generated.expected := helper", "forbidden", False, id="transitive_axiom"),
    *[pytest.param(f"import Lean\ndef {name} : Nat := 0\ntheorem Proofs.migrationCorrect : True := trivial",
                   name, False, id=f"changed_protected_{label}", marks=pytest.mark.approval)
      for label, name in [("contract", "Requirements.contract"), ("SQL", "Generated.script"),
                          ("schema", "Generated.startSchema"), ("profile", "Generated.profile")]],
    pytest.param("import Generated\nunsafe def Proofs.migrationCorrect : True := True.intro",
                 "Proofs.migrationCorrect", False, id="unsafe_proof"),
    # An explicit partial constant avoids elaboration into an ordinary opaque wrapper.
    # Lean.Replay omits partial constants; the required-proof lookup must then reject it.
    pytest.param("import Lean\nimport Generated\nrun_elab Lean.addDecl (.defnDecl { "
                 "name := `Proofs.migrationCorrect, levelParams := [], type := Lean.mkConst `True, "
                 "value := Lean.mkConst `True.intro, hints := .opaque, safety := .partial })",
                 "missing required declaration: Proofs.migrationCorrect", False, id="partial_proof"),
])
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
