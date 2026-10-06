"""Shared private compiled kernel fixtures for both proof acceptance paths."""

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
import os
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult, copy_mutable_tree, run_command

FIXTURES = Path(__file__).with_name("kernel_gate")


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


