"""Prepare the inputs for the Lake artifact-cache experiment.

Usage: python3 experiments/lake-cache/setup_shim.py WORK_DIR

Creates under WORK_DIR:

- `generated-small/`, `generated-atuin/`: generated `SchemaInputs`/`SqlInputs`/`Generated`
  sources, written by `migration-check verify --artifacts`.
- `runtime-lake/`: a read-only copy of the runtime's `.lake` that also contains
  `build/ir`. The shipped runtime omits `ir`, and Lake then treats every
  `SqliteVerifier` module as not built, because each trace lists a `.c` output.
  This simulates a runtime that ships `ir`.
- `shim/`: library-only Lake packages for `SqliteVerifier` and `belaySqlite`. They
  point at the runtime's sources and outputs and set `enableArtifactCache = false`,
  so Lake never tries to copy read-only library outputs into the cache. The
  runtime's own lakefile cannot be used: it requires `lean4export`, which the
  runtime does not ship.
"""

import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = (ROOT / "build" / "runtime").resolve()
EXAMPLES = ROOT / "examples"

SQLITE_VERIFIER_LAKEFILE = '''name = "sqliteVerifier"
version = "0.1.0"
enableArtifactCache = false

[[require]]
name = "belaySqlite"
path = "packages/belay-sqlite"

[[lean_lib]]
name = "SqliteVerifier"
roots = []
globs = {globs}
'''
"""Library-only package: the runtime's `SqliteVerifier` library without executables or lean4export."""


def generated_inputs(work: Path) -> None:
    """Write the generated sources of the small and Atuin examples with the installed CLI."""
    cases = {"small": ("3.51.0", EXAMPLES / "approved", EXAMPLES / "add_column_then_table", EXAMPLES / "approved"),
             "atuin": ("3.46.0", EXAMPLES / "atuin/approved", EXAMPLES / "atuin", EXAMPLES / "atuin")}
    for name, (profile, approved, candidate, schema) in cases.items():
        output = work / f"generated-{name}"
        shutil.rmtree(output, ignore_errors=True)
        subprocess.run([str(RUNTIME / "bin/migration-check"), "verify", "--profile", profile, "--format", "json",
                        "--schema", str(schema / "schema.sql"), "--requirements", str(approved / "Requirements.lean"),
                        "--interpretation", str(approved / "Interpretation.lean"),
                        "--migration", str(candidate / "migration.sql"),
                        "--next-interpretation", str(candidate / "NextInterpretation.lean"),
                        "--proofs", str(candidate / "Proofs.lean"), "--artifacts", str(output)],
                       check=True, capture_output=True, timeout=300)


def runtime_lake_with_ir(work: Path, shim: Path) -> None:
    """Copy the runtime's `.lake`, let Lake add `build/ir` for `SqliteVerifier`, then make it read-only."""
    target = work / "runtime-lake"
    if target.exists():
        for path in target.rglob("*"):
            path.chmod(path.stat().st_mode | stat.S_IWUSR)
        shutil.rmtree(target)
    shutil.copytree(RUNTIME / ".lake", target)
    for path in [target, *target.rglob("*")]:
        path.chmod(path.stat().st_mode | stat.S_IWUSR)
    (shim / ".lake").symlink_to(target)
    subprocess.run(["lake", "build", "SqliteVerifier"], cwd=shim, check=True, capture_output=True, timeout=600)
    for path in [target, *target.rglob("*")]:
        path.chmod(path.stat().st_mode & ~(stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))


def shim_packages(work: Path) -> Path:
    """Create the library-only `sqliteVerifier` and `belaySqlite` packages over the runtime."""
    shim = work / "shim"
    shutil.rmtree(shim, ignore_errors=True)
    belay_source, belay = RUNTIME / "packages/belay-sqlite", shim / "packages/belay-sqlite"
    belay.mkdir(parents=True)
    for name in ("SqliteVerifier", "SqliteVerifier.lean", "lean-toolchain"):
        (shim / name).symlink_to(RUNTIME / name)
    for name in ("Belay", ".lake", "lean-toolchain"):
        (belay / name).symlink_to(belay_source / name)
    lines = (belay_source / "lakefile.toml").read_text(encoding="utf-8").splitlines()
    (belay / "lakefile.toml").write_text("\n".join([*lines[:3], "enableArtifactCache = false", *lines[3:]]) + "\n")
    runtime_lakefile = (RUNTIME / "lakefile.toml").read_text(encoding="utf-8")
    globs = next(line.split("=", 1)[1].strip() for line in runtime_lakefile.splitlines()
                 if line.startswith("globs") and '"SqliteVerifier"' in line)
    (shim / "lakefile.toml").write_text(SQLITE_VERIFIER_LAKEFILE.format(globs=globs))
    return shim


if __name__ == "__main__":
    work = Path(sys.argv[1]).resolve()
    work.mkdir(parents=True, exist_ok=True)
    os.environ["PATH"] = f"{RUNTIME / 'lean/bin'}{os.pathsep}{os.environ['PATH']}"
    generated_inputs(work)
    runtime_lake_with_ir(work, shim_packages(work))
    print(f"shim ready: {work / 'shim'}")
