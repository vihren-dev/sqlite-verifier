"""`prepare`: agent-side bundle preparation for the ADR 0003 data path.

This is a convenience the agent may replace with its own tools; nothing it caches
is trusted by `verify-bundle`. It keeps a persistent agent workspace, compiles the
contract and candidate modules incrementally, and exports the proof closure with
the pinned lean4export, omitting declarations from the trusted library.

Candidate reuse is keyed along the topological compile order: changing a module
recompiles it and every module after it. This is simpler than a dependency graph
and never reuses a module whose inputs changed.
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
from .runtime import Runtime
from .source_closure import CompileError, Source, discover_sources, module_path
from .stage_store import StageStore, digest

EXPORT_ROOTS = ("Proofs.migrationCorrect", "Proofs.migrationViolated",
                "NextInterpretation.next", "NextInterpretation.failures")


def compile_candidates(*, order: tuple[str, ...], sources: Path, candidate: Path, trusted: Path,
                       cache: Path, base_key: str, runtime: Runtime, workspace: Path) -> tuple[int, int]:
    """Compile candidate modules in order, reusing cached outputs whose chained key matches."""
    key, compiled, reused = base_key, 0, 0
    for name in order:
        relative = module_path(name)
        source = (sources / relative).with_suffix(relative.suffix + ".lean").read_bytes()
        key = digest({"previous": key, "module": name, "source": source.hex()})
        entry = cache / key
        if not entry.is_dir():
            with TemporaryDirectory(prefix="module-", dir=workspace) as temporary:
                output = Path(temporary)
                compile_modules(order=(name,), sources=sources, destination=output, previous=(trusted, candidate),
                                sysroot=runtime.sysroot, library=runtime.library, workspace=workspace)
                cache.mkdir(parents=True, exist_ok=True)
                shutil.copytree(output, entry, dirs_exist_ok=True)
            compiled += 1
        else:
            reused += 1
        shutil.copytree(entry, candidate, dirs_exist_ok=True)
    return compiled, reused


def export_bundle(*, runtime: Runtime, trusted: Path, candidate: Path, trusted_imports: set[str],
                  output: Path, timeout: float) -> None:
    """Write the version-1 header line, then the library-omitted lean4export NDJSON."""
    environment = {"LEAN_SYSROOT": str(runtime.sysroot), "PATH": os.environ.get("PATH", ""),
                   "LEAN_PATH": os.pathsep.join(map(str, (runtime.sysroot / "lib/lean", runtime.library,
                                                          trusted, candidate)))}
    with output.open("w", encoding="utf-8") as stream:
        stream.write(json.dumps({"bundle": 1, "trusted_imports": sorted(trusted_imports)}) + "\n")
        stream.flush()
        result = subprocess.run([str(runtime.exporter), "--skip-trusted", "--ignore-missing", "Proofs", "--",
                                 *EXPORT_ROOTS], env=environment, stdout=stream, stderr=subprocess.PIPE,
                                text=True, timeout=timeout, check=False)
    if result.returncode:
        raise Rejection("UNVERIFIED", f"lean4export failed: {result.stderr.strip()}")


def prepare(options: argparse.Namespace) -> dict[str, object]:
    """Build the candidate against the approved contract and export a bundle to `--output`."""
    inputs = generated_inputs(options)
    runtime = Runtime.locate(inputs.profile.engine)
    if not runtime.exporter.is_file():
        raise Rejection("INPUT_ERROR", "This runtime has no lean4export; rebuild with ADR 0003 support")
    agent = options.workspace.resolve()
    agent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="prepare-", dir=agent) as temporary:
        workspace = Path(temporary)
        try:
            contract = compile_contract(
                sysroot=runtime.sysroot, library=runtime.library, requirements=options.requirements,
                interpretation=options.interpretation, schema_inputs=inputs.schema_source,
                sql_inputs=inputs.sql_source, workspace=workspace,
                store=StageStore(agent / "stage-store", approved_eligible=True))
            selected = [path.resolve(strict=True) for path in
                        (options.requirements, options.interpretation, options.next_interpretation, options.proofs)]
            sources, candidate = workspace / "candidate-sources", workspace / "candidate"
            for directory in (sources, candidate):
                directory.mkdir()
            external: set[str] = set()
            _, order = discover_sources(
                initial={"NextInterpretation": Source(selected[2], selected[2].read_bytes()),
                         "Proofs": Source(selected[3], selected[3].read_bytes()),
                         "Generated": Source(None, EXPECTED_SOURCE.encode())},
                roots=tuple(dict.fromkeys(path.parent for path in selected)), excluded=set(),
                forbidden={"SchemaInputs", "SqlInputs"},
                available=set(contract.modules) | {"SchemaInputs", "SqlInputs"},
                directory=sources, sysroot=runtime.sysroot, library=runtime.library, workspace=workspace,
                external=external)
            base_key = digest({"contract": contract.hashes, "runtime": [str(runtime.sysroot), str(runtime.library)]})
            compiled, reused = compile_candidates(
                order=order, sources=sources, candidate=candidate, trusted=contract.trusted,
                cache=agent / "modules", base_key=base_key, runtime=runtime, workspace=workspace)
        except CompileError as error:
            raise Rejection("UNVERIFIED", str(error)) from error
        export_bundle(runtime=runtime, trusted=contract.trusted, candidate=candidate,
                      trusted_imports=external | contract.external, output=options.output.resolve(), timeout=60)
    return {"status": "PREPARED", "bundle": str(options.output), "compiled_modules": compiled,
            "reused_modules": reused}
