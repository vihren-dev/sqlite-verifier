"""Independently selectable source staging, source closure and artifact-alias regressions."""

from collections.abc import Callable
import hashlib
import os
from pathlib import Path
import shutil
from unittest.mock import patch

import pytest

from migration_check.compile import artifact_bytes, compile_modules, compile_project
from migration_check.source_closure import CompileError, module_path
from belay.sqlite.sql_model import Column, Table
from migration_check.lean_inputs import schema_inputs
from tests.runtime_support import CommandResult
from tests.source_fixtures import (CompilationFixture, DEEPER, FIXTURES, HELPER,
                                   compilation_case, source_runtime_only)

pytestmark = [pytest.mark.kernel, pytest.mark.approval]


@pytest.mark.integration
@pytest.mark.requires_lean
def test_sealed_source_compilation(compilation_case: CompilationFixture, proof_checker: Path,
                                   command_runner: Callable[..., CommandResult]) -> None:
    """Source staging ignores forged generated/compiled inputs and preserves hashes through kernel checking."""
    case = compilation_case
    project = case.compile()
    assert project.hashes["approved/Odd.Module.lean"] == hashlib.sha256(HELPER).hexdigest()
    assert project.hashes["approved/Deeper.lean"] == hashlib.sha256(DEEPER).hexdigest()
    assert (project.trusted / "Odd.Module.olean").read_bytes() != b"untrusted compiled artifact"
    assert not (project.trusted / "lakefile.olean").exists()
    assert "approved/SchemaInputs.lean" not in project.hashes
    assert project.hashes["generated/SchemaInputs.lean"] == hashlib.sha256(schema_inputs(()).encode()).hexdigest()
    checked = command_runner([str(proof_checker), *map(str, case.libraries), str(project.trusted), str(project.candidate)],
                             cwd=case.root, timeout=30,
                             environment={**os.environ, "LEAN_SYSROOT": str(case.sysroot)})
    assert checked.returncode == 0, checked.diagnostic()


@pytest.mark.integration
@pytest.mark.requires_lean
def test_changed_supplied_schema(compilation_case: CompilationFixture) -> None:
    """An approved assertion about the supplied empty starting schema rejects a changed generated schema."""
    changed = schema_inputs((Table("unexpected", (Column("x", "text"),)),))
    with pytest.raises(CompileError) as rejected:
        compilation_case.compile(schema=changed)
    assert rejected.value.phase == "compile" and "Requirements" in str(rejected.value)
    assert "type mismatch" in str(rejected.value).lower(), str(rejected.value)


@pytest.mark.unit
def test_selected_generated_role(tmp_path: Path) -> None:
    """Generated SchemaInputs cannot be selected as an authored approved source role before tool use."""
    for name in ("SchemaInputs", "Interpretation", "NextInterpretation", "Proofs"):
        (tmp_path / f"{name}.lean").write_text("def forgedStartingSchema := True\n")
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    with pytest.raises(ValueError, match="reserved"):
        compile_project(sysroot=tmp_path, libraries=(tmp_path, tmp_path), requirements=tmp_path / "SchemaInputs.lean",
            interpretation=tmp_path / "Interpretation.lean", next_interpretation=tmp_path / "NextInterpretation.lean",
            proofs=tmp_path / "Proofs.lean", schema_inputs=schema_inputs(()), sql_inputs="", workspace=workspace)


@pytest.mark.integration
@pytest.mark.requires_lean
@pytest.mark.parametrize("module,diagnostic", [
    ("NextInterpretation", "reserved"), ("proofs", "reserved"), ("SqlInputs", "reserved"),
    ("Generated", "reserved"), ("schemainputs", "reserved"), ("SchemaInputs.Evil", "reserved"),
    ("HiddenCandidate", "escapes approved"), ("CandidateOnly", "Missing or conflicting"),
    ("Cycle", "cycle"), ("Conflict", "Missing or conflicting"),
], ids=["NextInterpretation", "proofs", "SqlInputs", "Generated", "schemainputs", "SchemaInputs.Evil",
        "HiddenCandidate", "CandidateOnly", "Cycle", "Conflict"])
def test_rejected_source_graph(module: str, diagnostic: str, compilation_case: CompilationFixture) -> None:
    """Forbidden roles, aliases, missing dependencies, cycles and conflicts reject before proof compilation."""
    case = compilation_case
    (case.approved / "HiddenCandidate.lean").hardlink_to(case.candidate / "Proofs.lean")
    original = (FIXTURES / "Requirements.lean").read_text()
    (case.approved / "Requirements.lean").write_text(f"import {module}\n" + original)
    (case.candidate / "CandidateOnly.lean").write_text("def invisible := 1\n")
    (case.approved / "Cycle.lean").write_text("import Requirements\n")
    second = case.root / "second"
    second.mkdir()
    shutil.copyfile(case.approved / "Interpretation.lean", second / "Interpretation.lean")
    (case.approved / "Conflict.lean").write_text("def value := 1\n")
    (second / "Conflict.lean").write_text("def value := 2\n")
    with patch("migration_check.compile.compile_modules") as compile_spy:
        with pytest.raises(ValueError, match=diagnostic):
            case.compile(interpretation=second / "Interpretation.lean")
        compile_spy.assert_not_called()


@pytest.mark.unit
def test_compiler_output_symlink(tmp_path: Path) -> None:
    """The trusted parent rejects an emitted symlink before copying a compiler artifact."""
    source = tmp_path / "Requirements.lean"
    source.write_text("def value := 1\n")
    destination = tmp_path / "destination"
    destination.mkdir()

    def emit_link(*args: object, **kwargs: object) -> str:
        """Model a malicious artifact without starting a compiler or requiring Lean installation."""
        output = args[4]
        assert isinstance(output, Path)
        (output / "Requirements.olean").symlink_to(source)
        return ""

    with patch("migration_check.compile.lean_process", emit_link), pytest.raises(CompileError) as rejected:
        compile_modules(order=("Requirements",), sources=tmp_path, destination=destination,
                        previous=(), sysroot=tmp_path, libraries=(tmp_path, tmp_path), workspace=tmp_path)
    assert rejected.value.phase == "artifact"


@pytest.mark.unit
@pytest.mark.parametrize("alias", ["parent_symlink", "hardlink"])
def test_artifact_alias(alias: str, tmp_path: Path) -> None:
    """Neither a linked parent directory nor an aliased regular file can escape the compiler output tree."""
    outside, nested = tmp_path / "outside", tmp_path / "nested"
    outside.mkdir()
    nested.mkdir()
    artifact = outside / "Bar.olean"
    artifact.write_bytes(b"outside artifact")
    if alias == "parent_symlink":
        (nested / "Foo").symlink_to(outside, target_is_directory=True)
        produced = nested / "Foo/Bar.olean"
    else:
        produced = nested / "hardlinked.olean"
        produced.hardlink_to(artifact)
    with pytest.raises(CompileError):
        artifact_bytes(produced, nested)


@pytest.mark.unit
def test_quoted_module_path() -> None:
    """A quoted Lean module segment containing a dot remains one filesystem segment."""
    assert module_path("Foo.«Bar.Baz»") == Path("Foo/Bar.Baz")
