"""Compile the trusted stages: generated schema, approved contract and generated SQL.

Shared by source `verify`, `verify-bundle` and `prepare`. Each stage may be restored
from an opt-in `StageStore` when eligible (ADR 0003, "Approved contract reuse");
otherwise it is compiled freshly with the pinned Lean.
"""

from dataclasses import dataclass
import hashlib
from pathlib import Path

from .baseline import check_baseline
from .cache_eligibility import approved_reuse_allowed
from .source_closure import Source, discover_sources, module_path, role_sources
from .stage_store import StageStore, runtime_identity, stage_key

APPROVED_FORBIDDEN = frozenset({"NextInterpretation", "Generated", "Proofs", "SqlInputs", "SchemaInputs"})


@dataclass(frozen=True)
class Contract:
    """A snapshotted approved closure, its compile order and its trusted-library imports."""

    sources: dict[str, Source]
    order: tuple[str, ...]
    external: frozenset[str]


def discover_contract(*, initial: dict[str, Source], roots: tuple[Path, ...], excluded: set[Path],
                      directory: Path, sysroot: Path, library: Path, workspace: Path) -> Contract:
    """Snapshot the approved closure reachable from Requirements and Interpretation."""
    external: set[str] = set()
    sources, order = discover_sources(
        initial=initial, roots=roots, excluded=excluded, forbidden=set(APPROVED_FORBIDDEN),
        available={"SchemaInputs"}, directory=directory, sysroot=sysroot, library=library,
        workspace=workspace, external=external)
    return Contract(sources, order, frozenset(external))


def source_hashes(stage: str, sources: dict[str, Source]) -> dict[str, str]:
    """Report hashes in the public `stage/Module.lean` form used by baselines and artifacts."""
    return {f"{stage}/{module_path(name)}.lean": hashlib.sha256(source.contents).hexdigest()
            for name, source in sources.items()}


def run_stage(*, stage: str, order: tuple[str, ...], sources: Path, destination: Path,
              previous: tuple[Path, ...], previous_keys: tuple[str, ...], sysroot: Path, library: Path,
              workspace: Path, store: StageStore | None, eligible: bool) -> tuple[list[str], str]:
    """Restore an eligible stage from the store or compile it, returning diagnostics and its key."""
    from .compile import compile_modules

    modules = {name: (sources / module_path(name)).with_suffix(module_path(name).suffix + ".lean").read_bytes()
               for name in order}
    key = stage_key(stage, modules, previous_keys, runtime_identity(sysroot, library))
    required = tuple(f"{module_path(name).as_posix()}.olean" for name in order)
    if store is not None and eligible and store.restore(key, destination, required):
        return [], key
    diagnostics = compile_modules(order=order, sources=sources, destination=destination,
                                  previous=previous, sysroot=sysroot, library=library, workspace=workspace)
    if store is not None and eligible:
        store.save(key, destination)
    return diagnostics, key


def compile_trusted(*, contract: Contract, approved_sources: Path, schema_inputs: str, sql_inputs: str | None,
                    trusted: Path, sysroot: Path, library: Path, workspace: Path,
                    store: StageStore | None) -> list[str]:
    """Compile schema, approved and SQL stages into `trusted`, reusing only eligible stages.

    With `sql_inputs=None` the SQL stage is skipped: the bundle checker constructs those
    declarations itself from the frontend's structural record.
    """
    sql_sources = workspace / "sql-sources"
    schema_output, sql_output = workspace / "schema-output", workspace / "sql-output"
    for directory in (sql_sources, schema_output, sql_output):
        directory.mkdir()
    # Starting schema has no access to approved or candidate sources/artifacts.
    (sql_sources / "SchemaInputs.lean").write_text(schema_inputs, encoding="utf-8")
    common = {"sysroot": sysroot, "library": library, "workspace": workspace, "store": store}
    diagnostics, schema_key = run_stage(stage="SchemaInputs", order=("SchemaInputs",), sources=sql_sources,
                                        destination=schema_output, previous=(), previous_keys=(),
                                        eligible=True, **common)
    approved_digest = hashlib.sha256(repr(sorted(source_hashes("approved", contract.sources).items()))
                                     .encode()).hexdigest()
    more, _ = run_stage(stage="approved", order=contract.order, sources=approved_sources,
                                   destination=trusted, previous=(schema_output,), previous_keys=(schema_key,),
                                   eligible=store is not None and approved_reuse_allowed(approved_digest, store),
                                   **common)
    diagnostics += more
    if sql_inputs is not None:
        (sql_sources / "SqlInputs.lean").write_text(sql_inputs, encoding="utf-8")
        more, _ = run_stage(stage="SqlInputs", order=("SqlInputs",), sources=sql_sources, destination=sql_output,
                            previous=(schema_output,), previous_keys=(schema_key,), eligible=True, **common)
        diagnostics += more
    for directory in (schema_output, sql_output):
        for artifact in directory.rglob("*"):
            if artifact.is_file():
                target = trusted / artifact.relative_to(directory)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(artifact.read_bytes())
                target.chmod(0o444)
    return diagnostics


@dataclass(frozen=True)
class CompiledContract:
    """Trusted stage outputs for the bundle path, with input hashes and trusted imports."""

    trusted: Path
    hashes: dict[str, str]
    external: frozenset[str]
    modules: frozenset[str]


def compile_contract(*, sysroot: Path, library: Path, requirements: Path, interpretation: Path,
                     schema_inputs: str, sql_inputs: str, workspace: Path, store: StageStore | None,
                     approved_baseline: Path | None = None, schema_hash: str | None = None,
                     compile_sql: bool = True) -> CompiledContract:
    """Check optional approval, then compile the trusted stages without any candidate source.

    `compile_sql=False` leaves `SqlInputs` uncompiled for the bundle checker to construct;
    its source hash is still reported.
    """
    selected = {"Requirements": requirements.resolve(strict=True),
                "Interpretation": interpretation.resolve(strict=True)}
    if any(path.stem.casefold() == "schemainputs" for path in selected.values()):
        raise ValueError("SchemaInputs is reserved for generated starting schema")
    approved_sources, trusted = workspace / "approved-sources", workspace / "trusted"
    for directory in (approved_sources, trusted):
        directory.mkdir()
    initial = role_sources(selected)
    contract = discover_contract(
        initial=initial,
        roots=tuple(dict.fromkeys(path.parent for path in selected.values())), excluded=set(),
        directory=approved_sources, sysroot=sysroot, library=library, workspace=workspace)
    hashes = source_hashes("approved", contract.sources)
    hashes["generated/SchemaInputs.lean"] = hashlib.sha256(schema_inputs.encode()).hexdigest()
    hashes["generated/SqlInputs.lean"] = hashlib.sha256(sql_inputs.encode()).hexdigest()
    if approved_baseline is not None:
        check_baseline(approved_baseline, {**hashes, **({"schema.sql": schema_hash} if schema_hash else {})})
    compile_trusted(contract=contract, approved_sources=approved_sources, schema_inputs=schema_inputs,
                    sql_inputs=sql_inputs if compile_sql else None, trusted=trusted, sysroot=sysroot, library=library,
                    workspace=workspace, store=store)
    return CompiledContract(trusted, hashes, contract.external, frozenset(contract.sources))
