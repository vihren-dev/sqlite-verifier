"""Private source copies for tests that import compiler and verifier implementation internals."""

from argparse import Namespace
from collections.abc import Callable
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import shutil

import pytest

from migration_check.cli import arguments
from migration_check.compile import CompiledProject, compile_project
from migration_check.runtime import Runtime
from migration_check.sql_model import schema_inputs, sql_inputs

FIXTURES = Path(__file__).resolve().parent / "kernel_gate"
HELPER = b"/- import Ignored -/\nimport Deeper\ndef approvedHelper : Nat := deeperValue\n"
DEEPER = b"def deeperValue : Nat := 7\n"


@pytest.fixture(autouse=True)
def source_runtime_only(pytestconfig: pytest.Config) -> None:
    """Implementation imports must never be presented as installed-entrypoint evidence."""
    if pytestconfig.getoption("runtime_variant") == "installed":
        pytest.fail("Source-only implementation test cannot run with --runtime-variant installed")


@dataclass(frozen=True)
class CompilationFixture:
    """One isolated approved/candidate graph and empty compilation workspace per scenario."""

    root: Path
    approved: Path
    candidate: Path
    workspace: Path
    sysroot: Path
    library: Path

    def compile(self, *, schema: str | None = None, requirements: Path | None = None,
                interpretation: Path | None = None) -> CompiledProject:
        """Invoke the real staged compiler with explicit immutable runtime paths."""
        return compile_project(sysroot=self.sysroot, library=self.library,
            requirements=requirements or self.approved / "Requirements.lean",
            interpretation=interpretation or self.approved / "Interpretation.lean",
            next_interpretation=self.candidate / "NextInterpretation.lean",
            proofs=self.candidate / "Proofs.lean", schema_inputs=schema if schema is not None else schema_inputs(()),
            sql_inputs=sql_inputs((), ()), workspace=self.workspace)


@pytest.fixture
def compilation_case(tmp_path: Path, lean_sysroot: Path, lean_library: Path) -> CompilationFixture:
    """Set up source aliases and generated-schema checks without compiling in setup."""
    root = tmp_path.resolve()
    approved, candidate, workspace = root / "approved", root / "candidate", root / "work"
    for directory in (approved, candidate, workspace):
        directory.mkdir()
    for name in ("Requirements", "Interpretation"):
        shutil.copyfile(FIXTURES / f"{name}.lean", approved / f"{name}.lean")
    for name in ("NextInterpretation", "Proofs"):
        shutil.copyfile(FIXTURES / f"{name}.lean", candidate / f"{name}.lean")
    (approved / "SchemaInputs.lean").write_text("def forgedStartingSchema := True\n")
    (approved / "Deeper.lean").write_bytes(DEEPER)
    (approved / "Odd.Module.lean").write_bytes(HELPER)
    (approved / "Odd.Module.olean").write_bytes(b"untrusted compiled artifact")
    (approved / "lakefile.lean").write_text("this is not a Lake project\n")
    requirement = approved / "Requirements.lean"
    requirement.write_text(requirement.read_text().replace("import SqliteVerifier",
        "import SqliteVerifier\nimport SchemaInputs\nimport «Odd.Module»") +
        '\nexample : Generated.startSchema = [] := rfl\n')
    return CompilationFixture(root, approved, candidate, workspace, lean_sysroot, lean_library)


@dataclass(frozen=True)
class BaselineFixture:
    """Fresh approved closure, source-byte hashes and public verifier arguments for one case."""

    approved: Path
    candidate: Path
    baseline: Path
    original: dict[Path, bytes]
    hashes: dict[str, str]
    options: Namespace


@pytest.fixture
def baseline_case(tmp_path: Path, runtime_root: Path, lean_sysroot: Path, lean_library: Path,
                  proof_checker: Path, example_factory: Callable[[str], Path],
                  monkeypatch: pytest.MonkeyPatch) -> BaselineFixture:
    """Redirect only runtime location; source parsing, closure discovery and verification remain real."""
    runtime = Runtime(runtime_root, lean_sysroot, lean_library,
                      runtime_root / "build/sqlite-parser", proof_checker)

    def locate(cls: type[Runtime], sqlite_version: str = "3.51.0") -> Runtime:
        """Bind the test's exact supported profile to the explicitly selected artifact root."""
        assert sqlite_version == "3.51.0"
        return runtime

    monkeypatch.setattr(Runtime, "locate", classmethod(locate))
    approved = example_factory("approved")
    candidate = example_factory("add_column_then_table")
    requirements = approved / "Requirements.lean"
    requirements.write_text("import Helper\n" + requirements.read_text())
    (approved / "Helper.lean").write_text("import Deeper\n")
    (approved / "Deeper.lean").write_text("def approvedVersion : Nat := 1\n")
    original = {path: path.read_bytes() for path in approved.glob("*.lean")}
    hashes = {f"approved/{path.name}": hashlib.sha256(contents).hexdigest()
              for path, contents in original.items()}
    schema = approved / "schema.sql"
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps({**hashes, "schema.sql": hashlib.sha256(schema.read_bytes()).hexdigest()}))
    values = ["verify", "--profile", "3.51.0", "--approved-baseline", str(baseline)]
    for name, path in {"schema": schema, "migration": candidate / "migration.sql",
            "requirements": requirements, "interpretation": approved / "Interpretation.lean",
            "next-interpretation": candidate / "NextInterpretation.lean",
            "proofs": candidate / "Proofs.lean"}.items():
        values.extend(["--" + name, str(path)])
    return BaselineFixture(approved, candidate, baseline, original, hashes, arguments(values))


@pytest.fixture
def invalid_baseline_case(baseline_case: BaselineFixture) -> BaselineFixture:
    """Keep an invalid candidate proof present in every early-rejection scenario."""
    proof = baseline_case.candidate / "Proofs.lean"
    proof.write_bytes(proof.read_bytes() + b"\ndef invalidProof : Nat := false\n")
    return baseline_case
