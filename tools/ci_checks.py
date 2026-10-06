"""Run the same fresh host gates with either checkout builds or explicit Nix artifacts."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from time import monotonic

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.check_resources import check_resources
from tests.runtime_support import CommandTimeout, run_command


def run_checks(scope: str, mode: str, system: str, root: Path) -> None:
    """Use Nix build/test targets while installed acceptance stays fresh."""
    if scope not in {"test", "package"} or mode not in {"source", "build"}:
        raise ValueError("CI requires a complete test/package recipe and a supported build mode")
    check_resources(root)
    if os.environ.get("SQLITE_VERIFIER_SYSTEM") != system:
        raise ValueError("Pinned shell system differs from the selected native CI system")
    environment = dict(os.environ)
    for variable in ("SQLITE_VERIFIER_RUNTIME_ROOT", "SQLITE_VERIFIER_UNIT_CHECKS"):
        environment.pop(variable, None)
    records: list[dict[str, object]] = []
    output = root / "build/ci-phases.json"
    output.parent.mkdir(exist_ok=True)

    def run(name: str, command: list[str], timeout: int, *, capture: bool = False) -> str:
        """Keep phase durations and failure status even when a native build or host gate fails."""
        started = monotonic()
        status = -1
        try:
            result = run_command(command, cwd=root, environment=environment, timeout=timeout,
                                 artifacts=root / "build/ci-phases" / name)
            status = result.returncode
            if not capture or status:
                print(result.stdout, end="", flush=True)
            print(result.stderr, end="", file=sys.stderr, flush=True)
            if status:
                raise subprocess.CalledProcessError(status, command, result.stdout, result.stderr)
            return result.stdout.strip()
        except CommandTimeout as error:
            status = error.result.returncode
            print(error.result.diagnostic(), file=sys.stderr, flush=True)
            raise
        finally:
            records.append({"phase": name, "command": command, "exit_code": status,
                            "elapsed_seconds": monotonic() - started})
            output.write_text(json.dumps(records, indent=2) + "\n")

    if mode == "build":
        environment["SQLITE_VERIFIER_RUNTIME_ROOT"] = run("runtime",
            ["nix-build", "build-support/default.nix", "-A", "runtime", "--no-out-link",
             "--extra-experimental-features", "nix-command flakes"], 900, capture=True)
        runtime = Path(environment["SQLITE_VERIFIER_RUNTIME_ROOT"])
    elif mode == "source":
        run("setup", ["just", "setup"], 330)
    else:
        raise ValueError(f"Unknown build mode: {mode}")
    toolchain = (runtime if mode == "build" else root) / "lean/bin"
    lean = str(toolchain / "lean") if toolchain.is_dir() else "lean"
    lake = str(toolchain / "lake") if toolchain.is_dir() else "lake"
    versions = {"python": sys.version,
                "lean": run("lean-version", [lean, "--version"], 10, capture=True),
                "lake": run("lake-version", [lake, "--version"], 10, capture=True)}
    (root / "build/ci-environment.json").write_text(json.dumps(versions, indent=2) + "\n")
    run("checks-" + scope, ["just", "test-full" if scope == "test" else scope], 1800)


def main() -> None:
    """Accept only the existing complete recipes and the two native supported platforms."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", choices=("test", "package"), required=True)
    parser.add_argument("--mode", choices=("source", "build"), default="source")
    parser.add_argument("--system", choices=("x86_64-linux", "aarch64-darwin"), required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    arguments = parser.parse_args()
    run_checks(arguments.scope, arguments.mode, arguments.system, arguments.root.resolve())


if __name__ == "__main__":
    main()
