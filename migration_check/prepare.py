"""`prepare`: agent-side bundle preparation for the ADR 0003 data path.

This is a convenience the agent may replace with its own tools; nothing it caches
is trusted by `verify-bundle`. It keeps a persistent agent workspace, compiles the
contract and candidate modules incrementally, and exports the proof closure with
the pinned lean4export, omitting declarations from the trusted library.

Candidate reuse follows each module's imports (`module_keys.py`): an edit
recompiles the edited module and the modules that import it, directly or
transitively, and nothing else.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

from .compile import EXPECTED_SOURCE, compile_modules
from .contract import compile_contract
from .diagnostics import Rejection
from .inputs import generated_inputs
from .import_path import merged_search_path
from .module_keys import contract_keys, module_keys
from .runtime import Runtime
from .source_closure import CompileError, Source, discover_sources, module_path, role_sources
from .stage_store import StageStore, runtime_identity

EXPORT_ROOTS = ("Proofs.migrationCorrect", "Proofs.migrationViolated",
                "NextInterpretation.next", "NextInterpretation.failures")
"""Positive/refutation proofs and interpretation inputs required by the bundle checker."""

PROTECTED_BASE_MODULE = "SqliteVerifier"
"""Protected library that GateCore.baseModules always imports for the verification target."""


def compile_candidates(*, order: tuple[str, ...], sources: Path, candidate: Path, trusted: Path,
                       cache: Path, keys: dict[str, str], runtime: Runtime, workspace: Path) -> tuple[int, int]:
    """Compile candidate modules in order, reusing cached outputs whose dependency-aware key matches."""
    compiled, reused = 0, 0
    for name in order:
        relative = module_path(name)
        entry = cache / keys[name]
        if not (entry / relative.parent / f"{relative.name}.olean").is_file():
            # Missing or incomplete entries are rebuilt; the verifier never trusts this cache.
            shutil.rmtree(entry, ignore_errors=True)
            with TemporaryDirectory(prefix="module-", dir=workspace) as temporary:
                output = Path(temporary)
                compile_modules(order=(name,), sources=sources, destination=output, previous=(trusted, candidate),
                                sysroot=runtime.sysroot, libraries=runtime.libraries, workspace=workspace)
                cache.mkdir(parents=True, exist_ok=True)
                shutil.copytree(output, entry, dirs_exist_ok=True)
            compiled += 1
        else:
            reused += 1
        shutil.copytree(entry, candidate, dirs_exist_ok=True)
    return compiled, reused


def export_bundle(*, runtime: Runtime, trusted: Path, candidate: Path, trusted_imports: set[str],
                  output: Path, timeout: float) -> None:
    """Use the header's trusted imports and protected base to omit exactly the checker library closure."""
    roots = (runtime.sysroot / "lib/lean", *runtime.libraries, trusted, candidate)
    requested = [module_path(name) for name in trusted_imports | {PROTECTED_BASE_MODULE}]
    requested.extend(path.relative_to(root).with_suffix("") for root in (trusted, candidate)
                     for path in root.rglob("*.olean"))
    with merged_search_path(roots, candidate.parent, requested=requested) as paths, output.open("w", encoding="utf-8") as stream:
        environment = {"LEAN_SYSROOT": str(runtime.sysroot), "PATH": os.environ.get("PATH", ""),
                       "LEAN_PATH": os.pathsep.join(map(str, paths))}
        stream.write(json.dumps({"bundle": 1, "trusted_imports": sorted(trusted_imports)}) + "\n")
        stream.flush()
        omitted = sorted(trusted_imports | {PROTECTED_BASE_MODULE})
        result = subprocess.run([str(runtime.exporter), *["--omit=" + module for module in omitted],
                                 "--ignore-missing", "Proofs", "--",
                                 *EXPORT_ROOTS], env=environment, stdout=stream, stderr=subprocess.PIPE,
                                text=True, timeout=timeout, check=False)
    if result.returncode:
        raise Rejection("UNVERIFIED", f"Proof exporter {runtime.exporter} failed: {result.stderr.strip()}; "
                        "check the candidate imports and proof declarations")


def prepare(options: argparse.Namespace) -> dict[str, object]:
    """Build the candidate against the approved contract and export a bundle to `--output`."""
    inputs = generated_inputs(options)
    runtime = Runtime.locate(inputs.profile.engine)
    if not runtime.exporter.is_file():
        raise Rejection("INPUT_ERROR", f"Proof exporter is missing: {runtime.exporter}; run just build or reinstall")
    agent = options.workspace.resolve()
    agent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="prepare-", dir=agent) as temporary:
        workspace = Path(temporary)
        try:
            contract = compile_contract(
                sysroot=runtime.sysroot, libraries=runtime.libraries, requirements=options.requirements,
                interpretation=options.interpretation, schema_inputs=inputs.schema_source,
                sql_inputs=inputs.sql_source, workspace=workspace,
                store=StageStore(agent / "stage-store", approved_eligible=True))
            selected = {"Requirements": options.requirements.resolve(strict=True),
                        "Interpretation": options.interpretation.resolve(strict=True),
                        "NextInterpretation": options.next_interpretation.resolve(strict=True),
                        "Proofs": options.proofs.resolve(strict=True)}
            # Same aliasing as `verify`: a file shared with an earlier role is imported, not repeated.
            roles = role_sources(selected)
            sources, candidate = workspace / "candidate-sources", workspace / "candidate"
            for directory in (sources, candidate):
                directory.mkdir()
            external: set[str] = set()
            imports: dict[str, tuple[str, ...]] = {}
            _, order = discover_sources(
                initial={"NextInterpretation": roles["NextInterpretation"], "Proofs": roles["Proofs"],
                         "Generated": Source(None, EXPECTED_SOURCE.encode())},
                roots=tuple(dict.fromkeys(path.parent for path in selected.values())), excluded=set(),
                forbidden={"SchemaInputs", "SqlInputs"},
                available=set(contract.modules) | {"SchemaInputs", "SqlInputs"},
                directory=sources, sysroot=runtime.sysroot, libraries=runtime.libraries, workspace=workspace,
                external=external, imports_out=imports)
            contract_key, sql_key = contract_keys(contract.hashes)
            keys = module_keys(
                order=order, imports=imports, contract_modules=contract.modules, contract_key=contract_key,
                sql_key=sql_key, runtime=runtime_identity(runtime.sysroot, runtime.libraries),
                sources={name: (sources / module_path(name)).with_suffix(module_path(name).suffix + ".lean")
                         .read_bytes() for name in order})
            compiled, reused = compile_candidates(
                order=order, sources=sources, candidate=candidate, trusted=contract.trusted,
                cache=agent / "modules", keys=keys, runtime=runtime, workspace=workspace)
        except CompileError as error:
            raise Rejection("UNVERIFIED", str(error)) from error
        export_bundle(runtime=runtime, trusted=contract.trusted, candidate=candidate,
                      trusted_imports=external | contract.external, output=options.output.resolve(), timeout=60)
    return {"status": "PREPARED", "bundle": str(options.output), "compiled_modules": compiled,
            "reused_modules": reused}
