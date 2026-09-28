"""Relocate copied Lean loader references before computing the signed dependency export."""

import os
from pathlib import Path
import stat

from runtime_dependencies import is_elf, run


def staged_reference(reference: str, binary: Path, source_lean: Path, staged_lean: Path) -> str:
    """Map only the original bundled tree to an existing, confined staged target."""
    source = source_lean.resolve(strict=True)
    candidate = Path(reference)
    if not candidate.is_absolute() or not candidate.is_relative_to(source):
        return reference
    if not candidate.resolve().is_relative_to(source):
        raise ValueError(f"Bundled loader reference escapes source Lean: {reference}")
    destination = staged_lean / candidate.relative_to(source)
    resolved = destination.resolve(strict=True)
    if not resolved.is_relative_to(staged_lean.resolve(strict=True)):
        raise ValueError(f"Bundled loader reference escapes staged Lean: {reference}")
    return "$ORIGIN/" + os.path.relpath(resolved, binary.parent)


def relocate_elf(files: list[Path], source_lean: Path, staged_lean: Path) -> None:
    """Patch copied ELF search paths and absolute dependencies without modifying store inputs."""
    for binary in files:
        if not is_elf(binary):
            continue
        rpath = run(["patchelf", "--print-rpath", str(binary)]).strip()
        relocated = ":".join(staged_reference(part, binary, source_lean, staged_lean)
                             for part in rpath.split(":"))
        needed = run(["patchelf", "--print-needed", str(binary)]).splitlines()
        replacements = [(name, staged_reference(name, binary, source_lean, staged_lean)) for name in needed]
        mode = stat.S_IMODE(binary.stat().st_mode)
        try:
            binary.chmod(mode | stat.S_IWUSR)
            if relocated != rpath:
                run(["patchelf", "--set-rpath", relocated, str(binary)])
            for original, replacement in replacements:
                if original != replacement:
                    run(["patchelf", "--replace-needed", original, replacement, str(binary)])
        finally:
            binary.chmod(mode)
