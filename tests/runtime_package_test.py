"""Install the actual native archive and exercise its sealed verifier under a clean environment."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
from tempfile import TemporaryDirectory
from time import monotonic


def checked(arguments: list[str], environment: dict[str, str], timeout: int = 180) -> subprocess.CompletedProcess[str]:
    """Bound archive installation and verification while preserving actionable output."""
    result = subprocess.run(arguments, env=environment, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise AssertionError(f"{arguments}: {result.stdout}{result.stderr}")
    return result


def main(archive: Path) -> None:
    """Prove packaging uses its own runtime with real positive, negative and unsupported inputs."""
    nix = Path(shutil.which("nix") or "missing-nix").absolute()
    with TemporaryDirectory(prefix="runtime package smoke ") as temporary:
        started = monotonic()
        root = Path(temporary).resolve()
        with tarfile.open(archive) as contents:
            contents.extractall(root, filter="data")
        bundle = next(path for path in root.iterdir() if path.is_dir())
        destination = root / "installed verifier"
        environment = {"HOME": str(root), "PATH": f"{nix.parent}:/usr/bin:/bin", "LANG": "C.UTF-8"}
        checked([str(bundle / "install.sh"), str(destination)], environment, timeout=300)
        print(f"Runtime extraction and installation: {monotonic() - started:.2f}s", flush=True)
        # Ambient imports and Lean selection must not affect the installed entrypoint.
        poison = root / "poison"
        poison.mkdir()
        (poison / "json.py").write_text('raise RuntimeError("ambient Python imported")\n')
        environment.update({"PYTHONPATH": str(poison), "LEAN_PATH": str(poison),
                            "MIGRATION_CHECK_LEAN_SYSROOT": str(poison), "PATH": "/usr/bin:/bin"})
        examples = destination / "examples"
        approved = examples / "approved"
        for parser, version in (("sqlite-parser", "3.51.0"), ("sqlite-parser-3.46.0", "3.46.0")):
            parsed = checked([str(destination / "build" / parser), str(approved / "schema.sql")],
                             environment, timeout=10)
            assert json.loads(parsed.stdout)["profile"] == version, parsed.stdout
        executable = destination / "bin/migration-check"
        for candidate, expected in (("add_column_then_table", "VERIFIED"),
                                    ("missing_required_column", "VIOLATED")):
            folder = examples / candidate
            arguments = [str(executable), "verify", "--profile", "3.51.0", "--format", "json",
                "--schema", str(approved / "schema.sql"),
                "--requirements", str(approved / "Requirements.lean"),
                "--interpretation", str(approved / "Interpretation.lean"),
                "--migration", str(folder / "migration.sql"),
                "--next-interpretation", str(folder / "NextInterpretation.lean"),
                "--proofs", str(folder / "Proofs.lean")]
            result = subprocess.run(arguments, env=environment, capture_output=True, text=True, timeout=180)
            assert json.loads(result.stdout)["status"] == expected, result.stdout + result.stderr
            assert (result.returncode == 0) == (expected == "VERIFIED"), result
        unsupported = root / "unsupported.sql"
        unsupported.write_text("DROP TABLE invoices;\n")
        arguments[arguments.index("--migration") + 1] = str(unsupported)
        result = subprocess.run(arguments, env=environment, capture_output=True, text=True, timeout=30)
        assert result.returncode != 0 and json.loads(result.stdout)["status"] == "UNSUPPORTED", result
        assert (destination / ".nix-roots").is_dir()
        # Reuse the actual pilot's public-interface checks with ambient tools removed.
        started = monotonic()
        subprocess.run([sys.executable, "-I", "-u", str(Path(__file__).with_name("atuin_cli_test.py")),
                        str(destination)], env=environment, timeout=1500, check=True)
        print(f"Installed Atuin checks: {monotonic() - started:.2f}s", flush=True)
        print("Runtime package: offline installation, isolated positive/refuted/unsupported checks passed")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: runtime_package_test.py ARCHIVE")
    main(Path(sys.argv[1]).resolve(strict=True))
