"""Bounded real-sandbox regressions for source closure and sealed module compilation."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
from unittest.mock import patch

from migration_check.compile import artifact_bytes, compile_modules, compile_project
from migration_check.source_closure import CompileError, module_path
from migration_check.sql_model import Column, Table, schema_inputs as emit_schema, sql_inputs as emit_sql

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/kernel_gate"
LIBRARY = ROOT / ".lake/build/lib/lean"


def main() -> None:
    """Check actual compiler isolation, trusted dependency hashes and rejected source graphs."""
    prefix = subprocess.run(["lean", "--print-prefix"], cwd=ROOT, capture_output=True,
                            text=True, check=True, timeout=10).stdout.strip()
    sysroot = Path(prefix).resolve(strict=True)
    with TemporaryDirectory(prefix="compilation-test-") as temporary:
        root = Path(temporary).resolve()
        approved, candidates = root / "approved", root / "candidates"
        approved.mkdir()
        candidates.mkdir()
        for name in ("Requirements", "Interpretation"):
            shutil.copyfile(FIXTURES / f"{name}.lean", approved / f"{name}.lean")
        for name in ("NextInterpretation", "Proofs"):
            shutil.copyfile(FIXTURES / f"{name}.lean", candidates / f"{name}.lean")
        schema_inputs, sql_inputs = emit_schema(()), emit_sql((), ())
        (approved / "SchemaInputs.lean").write_text("def forgedStartingSchema := True\n")
        workspace = root / "work"
        workspace.mkdir()
        requirement = approved / "Requirements.lean"
        original = requirement.read_text()
        helper = b"/- import Ignored -/\nimport Deeper\ndef approvedHelper : Nat := deeperValue\n"
        deeper = b"def deeperValue : Nat := 7\n"
        (approved / "Deeper.lean").write_bytes(deeper)
        (approved / "Odd.Module.lean").write_bytes(helper)
        (approved / "Odd.Module.olean").write_bytes(b"untrusted compiled artifact")
        (approved / "lakefile.lean").write_text("this is not a Lake project\n")
        protected_artifact = workspace / "trusted/Requirements.olean"
        requirement.write_text(original.replace("import SqliteVerifier", "import SqliteVerifier\nimport SchemaInputs\nimport «Odd.Module»") +
            f'\n#eval do\n  let readable ← try\n    let _ ← IO.FS.readFile "{candidates / "Proofs.lean"}"\n    pure true\n  catch _ => pure false\n'
            '  if readable then throw (IO.userError "candidate source leaked into approved compilation")\n'
            'example : Generated.startSchema = [] := rfl\n')
        next_source = candidates / "NextInterpretation.lean"
        next_source.write_text(next_source.read_text() +
            f'\n#eval do\n  let writable ← try\n    IO.FS.writeFile "{protected_artifact}" "changed"\n    pure true\n  catch _ => pure false\n'
            '  if writable then throw (IO.userError "candidate modified protected artifact")\n')
        arguments = dict(sysroot=sysroot, library=LIBRARY, requirements=requirement,
            interpretation=approved / "Interpretation.lean", next_interpretation=next_source,
            proofs=candidates / "Proofs.lean", schema_inputs=schema_inputs, sql_inputs=sql_inputs)
        project = compile_project(**arguments, workspace=workspace)
        assert project.hashes["approved/Odd.Module.lean"] == hashlib.sha256(helper).hexdigest()
        assert project.hashes["approved/Deeper.lean"] == hashlib.sha256(deeper).hexdigest()
        assert (project.trusted / "Odd.Module.olean").read_bytes() != b"untrusted compiled artifact"
        assert not (project.trusted / "lakefile.olean").exists()
        assert "approved/SchemaInputs.lean" not in project.hashes
        assert project.hashes["generated/SchemaInputs.lean"] == hashlib.sha256(schema_inputs.encode()).hexdigest()
        checked = subprocess.run([str(ROOT / ".lake/build/bin/migration-proof-checker"),
            str(LIBRARY), str(project.trusted), str(project.candidate)], cwd=ROOT,
            env={**os.environ, "LEAN_SYSROOT": str(sysroot)}, capture_output=True,
            text=True, timeout=30)
        assert checked.returncode == 0, checked.stderr

        changed_workspace = root / "changed-schema"
        changed_workspace.mkdir()
        try:
            compile_project(**{**arguments, "schema_inputs": emit_schema((Table("unexpected", (Column("x", "text"),)),))},
                            workspace=changed_workspace)
        except CompileError as error:
            assert error.phase == "compile" and "Requirements" in str(error)
            assert "type mismatch" in str(error).lower(), str(error)
        else:
            raise AssertionError("approved start-schema assertion ignored changed supplied schema")
        selected_shadow = root / "selected-shadow"
        selected_shadow.mkdir()
        try:
            compile_project(**{**arguments, "requirements": approved / "SchemaInputs.lean"},
                            workspace=selected_shadow)
        except ValueError as error:
            assert "reserved" in str(error)
        else:
            raise AssertionError("generated module accepted as a selected source role")

        # Header dependency errors must precede any proof compilation.
        (approved / "HiddenCandidate.lean").hardlink_to(candidates / "Proofs.lean")
        for index, (extra, diagnostic) in enumerate((
            ("import NextInterpretation", "reserved"),
            ("import proofs", "reserved"),
            ("import SqlInputs", "reserved"),
            ("import Generated", "reserved"),
            ("import schemainputs", "reserved"),
            ("import SchemaInputs.Evil", "reserved"),
            ("import HiddenCandidate", "escapes approved"),
            ("import CandidateOnly", "Missing or conflicting"),
            ("import Cycle", "cycle"),
            ("import Conflict", "Missing or conflicting"),
        )):
            requirement.write_text(extra + "\n" + original)
            (candidates / "CandidateOnly.lean").write_text("def invisible := 1\n")
            (approved / "Cycle.lean").write_text("import Requirements\n")
            second = root / "second"
            second.mkdir(exist_ok=True)
            shutil.copyfile(approved / "Interpretation.lean", second / "Interpretation.lean")
            (approved / "Conflict.lean").write_text("def value := 1\n")
            (second / "Conflict.lean").write_text("def value := 2\n")
            rejected_workspace = root / f"rejected-{index}"
            rejected_workspace.mkdir()
            try:
                compile_project(**{**arguments, "interpretation": second / "Interpretation.lean"},
                                workspace=rejected_workspace)
            except ValueError as error:
                assert diagnostic in str(error), (diagnostic, str(error))
            else:
                raise AssertionError(f"accepted source graph: {extra}")

        # Never follow a compiler-produced link when copying outputs in the trusted parent.
        def emit_link(*args: object, **kwargs: object) -> str:
            """Simulate a malicious emitted artifact without executing adversarial native code."""
            output = args[4]
            assert isinstance(output, Path)
            (output / "Requirements.olean").symlink_to(requirement)
            return ""

        destination = root / "link-output"
        destination.mkdir()
        with patch("migration_check.compile.lean_process", emit_link):
            try:
                compile_modules(order=("Requirements",), sources=approved, destination=destination,
                    previous=(), sysroot=sysroot, library=LIBRARY, workspace=root)
            except CompileError as error:
                assert error.phase == "artifact"
            else:
                raise AssertionError("followed compiler-produced symlink")
        outside = root / "outside"
        outside.mkdir()
        (outside / "Bar.olean").write_bytes(b"outside artifact")
        nested = root / "nested-output"
        nested.mkdir()
        (nested / "Foo").symlink_to(outside, target_is_directory=True)
        linked = nested / "hardlinked.olean"
        linked.hardlink_to(outside / "Bar.olean")
        for produced in (nested / "Foo/Bar.olean", linked):
            try:
                artifact_bytes(produced, nested)
            except CompileError:
                pass
            else:
                raise AssertionError(f"followed aliased compiler artifact: {produced}")
    assert module_path("Foo.«Bar.Baz»") == Path("Foo/Bar.Baz")
    print("Compilation staging: real sandbox, source hashes, closure rejection and artifact checks passed.")


if __name__ == "__main__":
    main()
