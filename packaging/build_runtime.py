"""Build a native offline runtime archive after the shared verification checks pass."""

from collections.abc import Iterable
import hashlib
import os
from pathlib import Path
import platform
import shutil
import sys
import tarfile
from tempfile import TemporaryDirectory
from time import monotonic

from runtime_dependencies import lean_runtime_files, native_dependencies, run, runtime_file, store_path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_resources import check_resources


def copy_runtime(source: Path, destination: Path, files: Iterable[Path] | None = None) -> None:
    """Preserve the complete supported Lean import surface and executable permissions."""
    for path in (source.rglob("*") if files is None else files):
        if path.is_file() and runtime_file(path):
            target = destination / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def project_runtime_files(root: Path) -> list[Path]:
    """Do not ship Lake artifacts left behind after a project module is deleted."""
    library = root / ".lake/build/lib/lean"
    files: list[Path] = []
    for source in [*root.glob("*.lean"), *(root / "SqliteVerifier").rglob("*.lean")]:
        module = library / source.relative_to(root).with_suffix("")
        if not module.with_suffix(".olean").is_file():
            raise ValueError(f"Current module has not been built: {source}")
        for suffix in (".olean", ".olean.private", ".olean.server", ".ir", ".ir.sig"):
            artifact = module.with_suffix(suffix)
            if artifact.is_file():
                files.append(artifact)
    return files


def build() -> Path:
    """Bundle pinned interpreter, proof checker, grammar, Python and sandbox dependencies."""
    check_resources(ROOT)
    systems = {("Darwin", "arm64"): "aarch64-darwin", ("Linux", "x86_64"): "x86_64-linux"}
    system = systems[(platform.system(), platform.machine())]
    python = Path(sys.executable).resolve(strict=True)
    roots = {store_path(python)}
    sandbox_path = ""
    if system == "x86_64-linux":
        sandbox = Path(shutil.which("bwrap") or "missing-bubblewrap").resolve(strict=True)
        roots.add(store_path(sandbox))
        sandbox_path = str(sandbox.parent)
    lean = Path(run(["lean", "--print-prefix"]).strip()).resolve(strict=True)
    if not run([str(lean / "bin/lean"), "--version"]).startswith("Lean (version 4.33.0,"):
        raise ValueError("Pinned Lean runtime required")
    native = [ROOT / "build/sqlite-parser", ROOT / ".lake/build/bin/migration-proof-checker",
              ROOT / "build/sqlite-parser-3.46.0"]
    loader_roots, loader_report = native_dependencies([*native, lean / "bin/lean"], lean)
    roots |= loader_roots
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    archive = dist / f"sqlite-verifier-{system}.tar.gz"
    with TemporaryDirectory(prefix="runtime-bundle-") as temporary:
        started = monotonic()
        bundle = Path(temporary) / f"sqlite-verifier-{system}"
        payload = bundle / "payload"
        payload.mkdir(parents=True)
        for directory in ("migration_check", "examples", "docs"):
            shutil.copytree(ROOT / directory, payload / directory,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        for name in ("LICENSE", "lean-toolchain"):
            shutil.copy2(ROOT / name, payload / name)
        copy_runtime(ROOT / ".lake/build/lib/lean", payload / ".lake/build/lib/lean",
                     project_runtime_files(ROOT))
        copy_runtime(lean / "lib", payload / "lean/lib", lean_runtime_files(lean))
        for notice in ("LICENSE", "LICENSES"):
            shutil.copy2(lean / notice, payload / "lean" / notice)
        for source, relative in [(lean / "bin/lean", "lean/bin/lean"),
                                 (native[0], "build/sqlite-parser"),
                                 (native[1], ".lake/build/bin/migration-proof-checker"),
                                 (native[2], "build/sqlite-parser-3.46.0")]:
            target = payload / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        (payload / "bin").mkdir()
        launcher = payload / "bin/migration-check"
        launcher.write_text(f'''#!{python} -I
"""Run the installed verifier with pinned tools and isolated Python imports."""
import os
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
os.environ["MIGRATION_CHECK_LEAN_SYSROOT"] = str(root / "lean")
os.environ["PATH"] = {os.pathsep.join(filter(None, [sandbox_path, str(python.parent)]))!r}
sys.path.insert(0, str(root))
from migration_check.cli import main
raise SystemExit(main(sys.argv[1:]))
''')
        launcher.chmod(0o755)
        for name in ("install.sh", "install.py"):
            shutil.copy2(ROOT / "packaging" / name, bundle / name)
        shutil.copy2(ROOT / "docs/install.md", bundle / "README.md")
        (bundle / "platform").write_text(system + "\n")
        (bundle / "python-path").write_text(str(python) + "\n")
        (bundle / "nix-paths").write_text("\n".join(map(str, sorted(roots))) + "\n")
        (payload / "native-dependencies.txt").write_text(loader_report)
        (payload / "lean/nix-runtime-roots").write_text(
            "".join(str(path) + "\n" for path in sorted(loader_roots)))
        print(f"Runtime payload copying: {monotonic() - started:.2f}s", flush=True)
        started = monotonic()
        run(["nix", "--extra-experimental-features", "nix-command", "--offline", "copy",
             "--to", (bundle / "nix-cache").as_uri(), *map(str, sorted(roots))], timeout=300)
        print(f"Runtime Nix export: {monotonic() - started:.2f}s", flush=True)
        started = monotonic()
        run(["nix", "--extra-experimental-features", "nix-command", "--offline", "store", "verify",
             "--store", (bundle / "nix-cache").as_uri(), "--all", "--sigs-needed", "1"], timeout=300)
        print(f"Runtime signature verification: {monotonic() - started:.2f}s", flush=True)
        started = monotonic()
        with tarfile.open(archive, "w:gz", compresslevel=1) as output:
            output.add(bundle, arcname=bundle.name)
        print(f"Runtime archive compression: {monotonic() - started:.2f}s", flush=True)
    if archive.stat().st_size >= 2_000_000_000:
        raise ValueError("Archive exceeds the release asset size limit")
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    archive.with_suffix(archive.suffix + ".sha256").write_text(f"{digest}  {archive.name}\n")
    return archive


if __name__ == "__main__":
    print(build())
