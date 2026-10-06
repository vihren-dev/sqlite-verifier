"""Locate installed trusted executables separately from caller-supplied proof sources."""

from dataclasses import dataclass
import os
from pathlib import Path
import subprocess
from typing import Final

from .diagnostics import Rejection


PINNED_LEAN_VERSION: Final[str] = "4.34.1"
"""Lean release used to build the installed library and both kernel gates."""


@dataclass(frozen=True)
class Runtime:
    """Pinned library, parser, and checker paths owned by the verifier installation."""

    root: Path
    sysroot: Path
    library: Path
    parser: Path
    checker: Path

    @property
    def bundle_checker(self) -> Path:
        """ADR 0003 data-path checker; it never compiles candidate source."""
        return self.root / ".lake/build/bin/migration-bundle-checker"

    @property
    def exporter(self) -> Path:
        """Repository exporter used by `prepare` with the checker's explicit trusted imports."""
        return self.root / ".lake/build/bin/migration-proof-exporter"

    @classmethod
    def locate(cls, sqlite_version: str = "3.51.0") -> "Runtime":
        """Resolve a development/install runtime, never a candidate Lake configuration."""
        parsers = {"3.51.0": "sqlite-parser", "3.46.0": "sqlite-parser-3.46.0"}
        if sqlite_version not in parsers:
            raise Rejection("UNSUPPORTED", f"No installed parser for SQLite {sqlite_version}")
        root = Path(__file__).resolve().parent.parent
        configured = os.environ.get("MIGRATION_CHECK_LEAN_SYSROOT")
        if configured:
            sysroot = Path(configured).resolve(strict=True)
        elif (root / "lean").is_dir():
            sysroot = (root / "lean").resolve(strict=True)
        else:
            found = subprocess.run(["lean", "--print-prefix"], cwd=root, capture_output=True,
                                   text=True, check=True, timeout=5)
            sysroot = Path(found.stdout.strip()).resolve(strict=True)
        version = subprocess.run([str(sysroot / "bin/lean"), "--version"], cwd=root,
                                 capture_output=True, text=True, check=True, timeout=5)
        if not version.stdout.startswith(f"Lean (version {PINNED_LEAN_VERSION},"):
            raise Rejection(
                "INPUT_ERROR",
                f"Lean runtime at {sysroot} reports {version.stdout.strip()!r}; "
                f"the verifier requires Lean {PINNED_LEAN_VERSION}. "
                "Reinstall the verifier. For a development checkout, set "
                f"MIGRATION_CHECK_LEAN_SYSROOT to a Lean {PINNED_LEAN_VERSION} installation.",
            )
        runtime = cls(root, sysroot, root / ".lake/build/lib/lean", root / "build" / parsers[sqlite_version],
                      root / ".lake/build/bin/migration-proof-checker")
        if not runtime.library.is_dir() or not runtime.parser.is_file() or not runtime.checker.is_file():
            raise Rejection("INPUT_ERROR", "Verifier runtime is incomplete; run just build or reinstall")
        return runtime
