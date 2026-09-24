"""Collect native runtime dependencies without relying on the build machine's PATH later."""

from pathlib import Path
import platform
import re
import subprocess


def run(arguments: list[str], timeout: int = 30) -> str:
    """Keep every packaging subprocess bounded and include its diagnostics on failure."""
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{arguments}: {result.stdout}{result.stderr}")
    return result.stdout


def store_path(path: Path) -> Path:
    """Reduce a runtime executable or library to its owning immutable Nix store path."""
    resolved = path.resolve(strict=True)
    if resolved.parts[:3] != ("/", "nix", "store") or len(resolved.parts) < 4:
        raise ValueError(f"Packaging must use the pinned Nix environment: {path}")
    return Path(*resolved.parts[:4])


def is_elf(path: Path) -> bool:
    """Distinguish Linux shared objects from linker scripts that also use .so names."""
    with path.open("rb") as source:
        return source.read(4) == b"\x7fELF"


def native_dependencies(executables: list[Path], lean: Path) -> tuple[set[Path], str]:
    """Retain Nix loader references; permit only bundled-relative or platform system libraries."""
    libraries = [path for path in (lean / "lib").rglob("*")
                 if path.is_file() and (path.name.endswith((".dylib", ".so")) or ".so." in path.name)]
    if platform.system() == "Linux":
        libraries = [path for path in libraries if is_elf(path)]
    roots: set[Path] = set()
    reports: list[str] = []
    for binary in executables + libraries:
        command = ["otool", "-L", str(binary)] if platform.system() == "Darwin" else ["ldd", str(binary)]
        report = run(command)
        reports.append(report)
        if "not found" in report:
            raise RuntimeError(f"Unresolved native dependency: {report}")
        for reference in re.findall(r"(?:/|@(?:rpath|loader_path|executable_path)/)[^\s()]+", report):
            if reference == str(binary) + ":":
                continue
            if reference.startswith("/nix/store/"):
                roots.add(store_path(Path(reference)))
            elif Path(reference).resolve().is_relative_to(lean / "lib") and runtime_file(Path(reference)):
                continue
            elif reference.startswith(("@rpath/", "@loader_path/", "@executable_path/",
                                       "/usr/lib/", "/System/", "/lib/", "/lib64/")):
                continue
            elif reference.rstrip(":") == str(binary):
                continue
            else:
                raise RuntimeError(f"Nonportable native loader reference: {reference}")
    return roots, "\n".join(reports)


def runtime_file(path: Path) -> bool:
    """Keep kernel-private objects, interpreter IR and shared libraries; omit build/editor data."""
    return path.name.endswith((".olean", ".olean.private", ".olean.server", ".ir", ".ir.sig",
                               ".dylib", ".so")) or ".so." in path.name
