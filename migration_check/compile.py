"""Snapshot and compile approved and candidate Lean sources in separate sandboxes."""

from dataclasses import dataclass
import hashlib
from pathlib import Path
from tempfile import TemporaryDirectory

from .baseline import check_baseline
from .source_closure import CompileError, Source, discover_sources, lean_process, module_path, file_identity

EXPECTED_SOURCE = """import Requirements
import Interpretation
import SqlInputs
import NextInterpretation
namespace Generated
/-- Authoring convenience; the trusted gate reconstructs this proposition independently. -/
def expected : Prop := SqliteVerifier.VerificationConditions
  startSchema nextSchema script Interpretation.admitted Requirements.contract
  Interpretation.current NextInterpretation.next NextInterpretation.failures profile
end Generated
"""


@dataclass(frozen=True)
class CompiledProject:
    """Sealed compiler outputs and source hashes for the parent's proof gate and baseline."""

    trusted: Path
    candidate: Path
    hashes: dict[str, str]
    diagnostics: tuple[str, ...]


def artifact_bytes(produced: Path, output: Path) -> bytes | None:
    """Reject filesystem aliases before the trusted parent reads a compiler output."""
    parts = produced.relative_to(output).parts
    if any(output.joinpath(*parts[:index]).is_symlink() for index in range(len(parts) + 1)):
        raise CompileError(str(produced), "artifact", "compiler emitted a symlink path")
    if not produced.exists():
        return None
    if (not produced.is_file() or not produced.resolve().is_relative_to(output)
            or produced.stat().st_nlink != 1):
        raise CompileError(str(produced), "artifact", "compiler artifact is not an isolated regular file")
    return produced.read_bytes()


def compile_modules(*, order: tuple[str, ...], sources: Path, destination: Path,
                    previous: tuple[Path, ...], sysroot: Path, library: Path,
                    workspace: Path) -> list[str]:
    """Copy only expected regular artifacts after each isolated compiler has exited."""
    diagnostics: list[str] = []
    for name in order:
        relative = module_path(name)
        source = sources / relative.with_suffix(relative.suffix + ".lean")
        with TemporaryDirectory(prefix="compiler-", dir=workspace) as temporary:
            output = Path(temporary).resolve()
            artifact = output / relative.with_suffix(relative.suffix + ".olean")
            artifact.parent.mkdir(parents=True, exist_ok=True)
            diagnostics.append(lean_process(
                sysroot, library, [*previous, destination], source, output,
                ["-R", str(sources), "-o", str(artifact)], "compile"))
            artifacts: dict[Path, bytes] = {}
            for extension in (".olean", ".olean.server", ".olean.private", ".ir", ".ir.sig"):
                produced = output / relative.with_suffix(relative.suffix + extension)
                contents = artifact_bytes(produced, output)
                if contents is not None:
                    artifacts[produced] = contents
            if artifact not in artifacts:
                raise CompileError(name, "artifact", "compiler did not emit its required .olean")
            for produced, contents in artifacts.items():
                target = destination / produced.relative_to(output)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(contents)
                target.chmod(0o444)
    return diagnostics


def compile_project(*, sysroot: Path, library: Path, requirements: Path,
                    interpretation: Path, next_interpretation: Path, proofs: Path,
                    schema_inputs: str, sql_inputs: str, workspace: Path,
                    approved_baseline: Path | None = None, schema_hash: str | None = None) -> CompiledProject:
    """Check optional approval against sealed closures before isolated source compilation."""
    sysroot, library, workspace = (path.resolve(strict=True) for path in (sysroot, library, workspace))
    if not all(path.is_dir() for path in (sysroot, library, workspace)):
        raise ValueError("Toolchain, library and workspace must be directories")
    if any(workspace.iterdir()):
        raise ValueError("Compilation workspace must be a fresh empty private directory")
    selected = {"Requirements": requirements.resolve(strict=True),
                "Interpretation": interpretation.resolve(strict=True),
                "NextInterpretation": next_interpretation.resolve(strict=True),
                "Proofs": proofs.resolve(strict=True)}
    if any(path.stem.casefold() == "schemainputs" for path in selected.values()):
        raise ValueError("SchemaInputs is reserved for generated starting schema")
    if not all(path.is_file() for path in selected.values()):
        raise ValueError("Lean inputs must be regular source files")
    trusted, candidate = workspace / "trusted", workspace / "candidate"
    approved_sources, candidate_sources = workspace / "approved-sources", workspace / "candidate-sources"
    sql_sources = workspace / "sql-sources"
    for directory in (trusted, candidate, approved_sources, candidate_sources, sql_sources):
        directory.mkdir()
    snapshots: dict[tuple[int, int], bytes] = {}
    for path in selected.values():
        identity = file_identity(path)
        if identity not in snapshots:
            snapshots[identity] = path.read_bytes()
    first_name: dict[tuple[int, int], str] = {}
    initial: dict[str, Source] = {}
    for name, path in selected.items():
        identity = file_identity(path)
        original = first_name.setdefault(identity, name)
        initial[name] = Source(path, snapshots[identity] if original == name else
                               f"import {original}\n".encode())
    approved, approved_order = discover_sources(
        initial={name: initial[name] for name in ("Requirements", "Interpretation")},
        roots=tuple(dict.fromkeys(selected[name].parent for name in ("Requirements", "Interpretation"))),
        excluded={selected[name] for name in ("NextInterpretation", "Proofs")
                  if file_identity(selected[name]) not in {file_identity(selected["Requirements"]),
                                                         file_identity(selected["Interpretation"])}},
        forbidden={"NextInterpretation", "Generated", "Proofs", "SqlInputs", "SchemaInputs"},
        available={"SchemaInputs"},
        directory=approved_sources, sysroot=sysroot, library=library, workspace=workspace)
    # Snapshot candidates before any elaboration, but do not expose them to approved processes.
    proposed, proposed_order = discover_sources(
        initial={**{name: initial[name] for name in ("NextInterpretation", "Proofs")},
                 "Generated": Source(None, EXPECTED_SOURCE.encode())},
        roots=tuple(dict.fromkeys(path.parent for path in selected.values())), excluded=set(),
        forbidden={"SchemaInputs", "SqlInputs"}, available=set(approved) | {"SchemaInputs", "SqlInputs"}, directory=candidate_sources,
        sysroot=sysroot, library=library, workspace=workspace)
    hashes = {f"{stage}/{module_path(name)}.lean": hashlib.sha256(source.contents).hexdigest()
              for stage, collection in (("approved", approved), ("candidate", proposed))
              for name, source in collection.items()}
    hashes["generated/SchemaInputs.lean"] = hashlib.sha256(schema_inputs.encode()).hexdigest()
    hashes["generated/SqlInputs.lean"] = hashlib.sha256(sql_inputs.encode()).hexdigest()
    if approved_baseline is not None:
        protected_hashes = {**hashes, **({"schema.sql": schema_hash} if schema_hash is not None else {})}
        check_baseline(approved_baseline, protected_hashes)
    # Starting schema has no access to approved or candidate sources/artifacts.
    (sql_sources / "SchemaInputs.lean").write_text(schema_inputs, encoding="utf-8")
    schema_output = workspace / "schema-output"
    schema_output.mkdir()
    diagnostics = compile_modules(order=("SchemaInputs",), sources=sql_sources,
        destination=schema_output, previous=(), sysroot=sysroot, library=library, workspace=workspace)
    diagnostics += compile_modules(order=approved_order, sources=approved_sources,
        destination=trusted, previous=(schema_output,), sysroot=sysroot, library=library, workspace=workspace)
    (sql_sources / "SqlInputs.lean").write_text(sql_inputs, encoding="utf-8")
    sql_output = workspace / "sql-output"
    sql_output.mkdir()
    diagnostics += compile_modules(order=("SqlInputs",), sources=sql_sources,
        destination=sql_output, previous=(schema_output,), sysroot=sysroot, library=library, workspace=workspace)
    for directory in (schema_output, sql_output):
        for artifact in directory.iterdir():
            (trusted / artifact.name).write_bytes(artifact.read_bytes())
            (trusted / artifact.name).chmod(0o444)
    diagnostics += compile_modules(order=proposed_order, sources=candidate_sources,
        destination=candidate, previous=(trusted,), sysroot=sysroot, library=library, workspace=workspace)
    return CompiledProject(trusted, candidate, hashes, tuple(text for text in diagnostics if text))
