"""Bind cold comparisons to actual runtime/input bytes and report observable host conditions."""

from collections.abc import Sequence
import hashlib
import json
import os
from pathlib import Path
import platform

from migration_check.structural import Json

MEASUREMENT_SOURCE_PATTERN = "bundle_measurement*.py"
"""Source modules that implement this measurement policy, acquisition and report pipeline."""


def file_sha256(path: Path) -> str:
    """Hash exact bytes in bounded chunks, including large installed compiler artifacts."""
    if not path.is_file():
        raise ValueError(f"Identity input is not a regular file: {path}; select a regular installed artifact")
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            result.update(block)
    return result.hexdigest()


def tree_identity(root: Path) -> dict[str, Json]:
    """Follow actual installed links once per target, retaining each directory reference and file hash."""
    root = root.resolve(strict=True)
    if not root.is_file() and not root.is_dir():
        raise ValueError(f"Identity input is not regular: {root}; select a file or source directory")
    references: dict[str, Json] = {}
    files: dict[str, Json] = {}
    visited: set[Path] = set()
    if root.is_file():
        files["."] = {"resolved": str(root), "bytes": root.stat().st_size,
                      "mode": root.stat().st_mode, "sha256": file_sha256(root)}
    directories = os.walk(root, followlinks=True, onerror=raise_walk_error) if root.is_dir() else ()
    for directory, names, leaves in directories:
        path = Path(directory)
        target = path.resolve(strict=True)
        relative = path.relative_to(root).as_posix()
        references[relative] = {"resolved": str(target), "mode": path.stat().st_mode}
        if target in visited:
            names.clear()
            continue
        visited.add(target)
        names.sort()
        for name in sorted(leaves):
            file = path / name
            if not file.is_file():
                raise ValueError(f"Runtime/input contains a nonregular file: {file}; choose immutable regular inputs")
            files[file.relative_to(root).as_posix()] = {
                "resolved": str(file.resolve(strict=True)), "bytes": file.stat().st_size, "mode": file.stat().st_mode,
                "sha256": file_sha256(file)}
    contents: dict[str, Json] = {"root": str(root), "directory_references": references, "files": files}
    contents["sha256"] = hashlib.sha256(json.dumps(contents, sort_keys=True).encode()).hexdigest()
    return contents


def raise_walk_error(error: OSError) -> None:
    """Unreadable directories invalidate identity acquisition instead of silently disappearing."""
    raise error


def evidence_identity(runtime: Path, inputs: Sequence[Path], observer: Path, python: Path) -> dict[str, Json]:
    """Hash the complete selected runtime and explicit source roots outside measured command wall time."""
    sources = sorted(Path(__file__).parent.glob(MEASUREMENT_SOURCE_PATTERN))
    return {"runtime": tree_identity(runtime),
            "inputs": {str(root.resolve(strict=True)): tree_identity(root) for root in inputs},
            "observer": {"path": str(observer.resolve(strict=True)), "sha256": file_sha256(observer)},
            "python": {"path": str(python.resolve(strict=True)), "sha256": file_sha256(python)},
            "measurement_sources": {str(path.resolve()): file_sha256(path) for path in sources}}


def host_identity() -> dict[str, Json]:
    """Keep platform, machine and CPU identities separate from per-invocation load observations."""
    return {"system": platform.system(), "release": platform.release(), "machine": platform.machine(),
            "node": platform.node(), "cpu_count": os.cpu_count(), "python": platform.python_version()}


def host_conditions() -> dict[str, Json]:
    """Record visible load and the explicit OS-cache observation limit without inventing cold residency."""
    try:
        load = [str(value) for value in os.getloadavg()]
    except OSError:
        load = []
    return {"load_average_1_5_15": load,
            "os_file_caches": "not flushed; file residency is not observed",
            "identity_reads": "complete runtime/input hashes occur outside timing before and after each path",
            "background_processes": "load averages observed; individual process activity is not observed"}


def empty_cache_directory(parent: Path, name: str) -> Path:
    """Require a new empty cache instead of cleaning a populated directory or reusing a warm one."""
    directory = parent / name
    if directory.exists():
        raise ValueError(f"Cold cache already exists: {directory}; preserve it and select a new trial directory")
    directory.mkdir(parents=True)
    if any(directory.iterdir()):
        raise ValueError(f"Cold cache is nonempty: {directory}; preserve the invalid trial")
    return directory.resolve()
