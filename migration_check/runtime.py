"""Locate installed trusted executables separately from caller-supplied proof sources."""

from dataclasses import dataclass
import os
from pathlib import Path
import subprocess

from .diagnostics import Rejection


@dataclass(frozen=True)
class Runtime:
    """Pinned library, parser, and checker paths owned by the verifier installation."""

    root: Path
    sysroot: Path
    library: Path
    parser: Path
    checker: Path

    @classmethod
    def locate(cls) -> "Runtime":
        """Resolve a development/install runtime, never a candidate Lake configuration."""
        root = Path(__file__).resolve().parent.parent
        configured = os.environ.get("MIGRATION_CHECK_LEAN_SYSROOT")
        if configured:
            sysroot = Path(configured).resolve(strict=True)
        else:
            found = subprocess.run(["lean", "--print-prefix"], cwd=root, capture_output=True,
                                   text=True, check=True, timeout=5)
            sysroot = Path(found.stdout.strip()).resolve(strict=True)
        version = subprocess.run([str(sysroot / "bin/lean"), "--version"], cwd=root,
                                 capture_output=True, text=True, check=True, timeout=5)
        if not version.stdout.startswith("Lean (version 4.33.0,"):
            raise Rejection("INPUT_ERROR", "The verifier requires the pinned Lean 4.33.0 runtime")
        runtime = cls(root, sysroot, root / ".lake/build/lib/lean", root / "build/sqlite-parser",
                      root / ".lake/build/bin/migration-proof-checker")
        if not runtime.library.is_dir() or not runtime.parser.is_file() or not runtime.checker.is_file():
            raise Rejection("INPUT_ERROR", "Verifier runtime is incomplete; run just build or reinstall")
        return runtime

    def read_roots(self) -> list[Path]:
        """Include dynamic-loader dependencies without granting caller/home-directory reads."""
        roots = [self.sysroot, self.library, self.checker.parent]
        for path in ("/usr/lib", "/lib", "/lib64"):
            if Path(path).exists():
                roots.append(Path(path))
        return roots
