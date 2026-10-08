"""Resolve Lean source imports with the pinned compiler's header parser."""

from collections.abc import Sequence
from contextlib import nullcontext
from dataclasses import dataclass
from graphlib import TopologicalSorter
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory

from .process import run_process
from .import_path import merged_search_path


class CompileError(RuntimeError):
    """A bounded compiler process rejected a module or failed to emit its artifact."""

    def __init__(self, module: str, phase: str, diagnostics: str) -> None:
        self.module, self.phase, self.diagnostics = module, phase, diagnostics
        super().__init__(f"{phase} {module}: {diagnostics}")


@dataclass(frozen=True)
class Source:
    """An immutable source snapshot, before any user elaborator can run."""

    path: Path | None
    contents: bytes


def file_identity(path: Path) -> tuple[int, int]:
    """Recognize case aliases and hardlinks as the same physical source file."""
    metadata = path.stat()
    return metadata.st_dev, metadata.st_ino


def role_sources(selected: dict[str, Path]) -> dict[str, Source]:
    """Snapshot each role's file once; a later role naming the same physical file imports the first.

    One file may supply several roles (for example both current and next
    interpretations). Compiling it twice would declare its contents twice, so only
    the first role in `selected` order gets the bytes.
    """
    snapshots: dict[tuple[int, int], bytes] = {}
    first_name: dict[tuple[int, int], str] = {}
    initial: dict[str, Source] = {}
    for name, path in selected.items():
        identity = file_identity(path)
        if identity not in snapshots:
            snapshots[identity] = path.read_bytes()
        original = first_name.setdefault(identity, name)
        initial[name] = Source(path, snapshots[identity] if original == name else f"import {original}\n".encode())
    return initial


def module_path(name: str) -> Path:
    """Decode Lean's printed module name; escaped dots remain filename characters."""
    components: list[str] = []
    component = ""
    escaped = False
    for character in name:
        if character == "«" and not escaped:
            escaped = True
        elif character == "»" and escaped:
            escaped = False
        elif character == "." and not escaped:
            components.append(component)
            component = ""
        else:
            component += character
    components.append(component)
    if escaped or any(not part or part in (".", "..") or
                      any(char in part for char in "/\\\x00") for part in components):
        raise ValueError(f"Unsafe module path: {name}")
    return Path(*components)


def lean_process(sysroot: Path, libraries: tuple[Path, Path], search: Sequence[Path], source: Path,
                 output: Path, arguments: Sequence[str], phase: str, timeout: float = 30) -> str:
    """Run only the pinned executable, with explicit paths and no ambient project settings."""
    roots = (sysroot / "lib/lean", *libraries, *search)
    dependency_header = "--deps-json" in arguments
    requested = () if dependency_header else tuple(module_path(name)
        for name in imports(source, sysroot, libraries, output))
    view = nullcontext(roots) if dependency_header else merged_search_path(roots, output, requested=requested)
    with view as paths:
        result = run_process(
            [str(sysroot / "bin/lean"), *arguments, str(source)],
            write_root=output,
            environment={"LEAN_SYSROOT": str(sysroot), "LEAN_PATH": os.pathsep.join(map(str, paths))},
            timeout=timeout,
        )
    if result.returncode:
        raise CompileError(str(source), phase, result.stdout + result.stderr)
    return result.stdout


def imports(source: Path, sysroot: Path, libraries: tuple[Path, Path], workspace: Path) -> tuple[str, ...]:
    """Read official dependency JSON without importing modules or executing their code."""
    with TemporaryDirectory(prefix="header-", dir=workspace) as temporary:
        text = lean_process(sysroot, libraries, [], source, Path(temporary).resolve(),
                            ["--deps-json"], "dependencies", timeout=5)
    parsed: object = json.loads(text)
    if not isinstance(parsed, dict) or not isinstance(parsed.get("imports"), list):
        raise ValueError("Invalid dependency JSON from pinned Lean")
    records = parsed["imports"]
    if len(records) != 1 or not isinstance(records[0], dict):
        raise ValueError("Expected exactly one Lean dependency result")
    record = records[0]
    if record.get("errors"):
        raise ValueError(f"Invalid Lean import header: {record['errors']}")
    result = record.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("imports"), list):
        raise ValueError("Missing Lean import list")
    names: list[str] = []
    for entry in result["imports"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("module"), str):
            raise ValueError("Invalid Lean import name")
        names.append(entry["module"])
    return tuple(dict.fromkeys(names))


def discover_sources(*, initial: dict[str, Source], roots: Sequence[Path],
                     excluded: set[Path], forbidden: set[str], available: set[str],
                     directory: Path, sysroot: Path, libraries: tuple[Path, Path],
                     workspace: Path, external: set[str] | None = None,
                     imports_out: dict[str, tuple[str, ...]] | None = None) -> tuple[dict[str, Source], tuple[str, ...]]:
    """Snapshot only reachable local sources and reject ambiguous or cyclic dependencies.

    When given, `external` collects imports resolved from the pinned sysroot or
    verifier libraries; exported bundles name these trusted modules instead of
    repeating their declarations. When given, `imports_out` receives each
    discovered module's complete import list, including contract and libraries
    modules, for dependency-aware rebuilds.
    """
    sources = dict(initial)
    excluded_ids = {file_identity(path) for path in excluded}
    forbidden_folded = {name.casefold() for name in forbidden}
    graph: dict[str, set[str]] = {}
    pending = list(initial)
    while pending:
        name = pending.pop()
        if name in graph:
            continue
        relative = module_path(name)
        if any(module_path(other).as_posix().casefold() == relative.as_posix().casefold()
               for other in graph if other != name):
            raise ValueError(f"Module names collide on supported filesystems: {name}")
        snapshot = directory / relative.with_suffix(relative.suffix + ".lean")
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes(sources[name].contents)
        dependencies = imports(snapshot, sysroot, libraries, workspace)
        if imports_out is not None:
            imports_out[name] = dependencies
        graph[name] = set()
        for dependency in dependencies:
            dep_path = module_path(dependency)
            if dependency in available:
                continue
            if dep_path.parts[0].casefold() in forbidden_folded:
                raise ValueError(f"Protected source {name} imports reserved module {dependency}")
            if any((base / dep_path).with_suffix(
                    dep_path.suffix + ".olean").is_file() for base in (sysroot / "lib/lean", *libraries)):
                if external is not None:
                    external.add(dependency)
                continue
            if dependency not in sources:
                choices: dict[tuple[int, int], Path] = {}
                for root in roots:
                    located = (root / dep_path).with_suffix(dep_path.suffix + ".lean")
                    if located.is_file():
                        choices[file_identity(located)] = located.resolve()
                if len(choices) != 1:
                    raise ValueError(f"Missing or conflicting source for module {dependency}")
                identity, origin = next(iter(choices.items()))
                if identity in excluded_ids or not any(origin.is_relative_to(root) for root in roots):
                    raise ValueError(f"Dependency escapes approved source roots: {dependency}")
                alias = next((key for key, value in sources.items()
                              if value.path is not None and file_identity(value.path) == identity), None)
                sources[dependency] = Source(origin, (f"import {alias}\n".encode()
                    if alias else origin.read_bytes()))
            graph[name].add(dependency)
            pending.append(dependency)
    return sources, tuple(TopologicalSorter(graph).static_order())
