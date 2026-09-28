"""Measure an unchanged legacy baseline and candidate on fresh, isolated native runners."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from time import monotonic

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.cache_fingerprint import ENVIRONMENT_FILES, cache_keys, fingerprint
from tests.runtime_support import CommandTimeout, run_command

BASELINE = "7a99c71f40c66077b2293e1ce2c8ef3151ce5d67"
SCENARIOS = ("cold", "warm", "python", "lean", "package")


def prepare(root: Path, variant: str, scenario: str, system: str, replica: int) -> dict[str, object]:
    """Describe exact source bytes and give each experiment an isolated store namespace."""
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True,
                              capture_output=True, text=True, timeout=10).stdout.strip()
    if variant == "baseline" and revision != BASELINE:
        raise ValueError("Benchmark baseline must be the reviewed optimized runtime")
    mutation = None
    if scenario in {"python", "lean"}:
        relative = "tests/test_translation.py" if scenario == "python" else "SqliteVerifier/Model.lean"
        path = root / relative
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        with path.open("a") as output:
            output.write("\n" + ("#" if scenario == "python" else "--") + " ADR 0001 input identity benchmark.\n")
        mutation = {"path": relative, "before": before, "after": hashlib.sha256(path.read_bytes()).hexdigest()}
    namespace = (f"adr1-benchmark-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}-"
                 f"{variant}-{system}-{replica}-")
    if variant == "candidate":
        keys = cache_keys(root, system)
        key, prefix = namespace + keys["key"], namespace + keys["prefix"]
    else:
        key = namespace + "dependencies-" + fingerprint(root, (root / name for name in ENVIRONMENT_FILES))
        prefix = ""
    return {"revision": revision, "variant": variant, "scenario": scenario, "system": system,
            "replica": replica, "mutation": mutation, "cache_key": key, "cache_prefix": prefix,
            "job_name": f"Benchmark ({variant}, {system}, {replica}, {scenario})",
            "runner": {name: os.environ.get(name) for name in
                       ("RUNNER_OS", "RUNNER_ARCH", "ImageOS", "ImageVersion")},
            "lean_pin": (root / "lean-toolchain").read_text().strip(),
            "baseline_case_timing": "unavailable: original legacy suites retained without instrumentation"
            if variant == "baseline" else None}


def execute(root: Path, report: Path) -> None:
    """Run original complete recipes and preserve raw phase and case reports on every outcome."""
    metadata = json.loads(report.read_text())
    helper = Path(__file__).with_name("ci_checks.py").resolve()
    command = ["nix", "develop", "path:./nix", "--command", "python3", str(helper),
               "--root", str(root), "--system", metadata["system"],
               "--scope", "package" if metadata["scenario"] == "package" else "test",
               "--mode", "build" if metadata["variant"] == "candidate" else "source"]
    started = monotonic()
    metadata["nix_version"] = subprocess.run(["nix", "--version"], check=True, capture_output=True,
                                           text=True, timeout=10).stdout.strip()
    metadata["cache"] = {name: os.environ.get(name) for name in ("CACHE_HIT", "RESTORED_KEY")}
    metadata["command"] = command
    metadata["exit_code"] = -1
    try:
        result = run_command(command, cwd=root, timeout=3900, artifacts=report.parent / "commands")
        report.with_suffix(".log").write_text(result.stdout + result.stderr)
        metadata["exit_code"] = result.returncode
        if result.returncode:
            raise subprocess.CalledProcessError(result.returncode, command)
    except CommandTimeout as error:
        metadata["exit_code"] = error.result.returncode
        report.with_suffix(".log").write_text(error.result.diagnostic())
        raise
    finally:
        metadata["command_elapsed_seconds"] = monotonic() - started
        report.write_text(json.dumps(metadata, indent=2) + "\n")
        if report.with_suffix(".log").exists():
            print(report.with_suffix(".log").read_text(errors="replace"), end="")


def main() -> None:
    """Keep matrix/event strings as structured arguments, never shell-evaluated fragments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("prepare", "execute"))
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--variant", choices=("baseline", "candidate"))
    parser.add_argument("--scenario", choices=SCENARIOS)
    parser.add_argument("--system", choices=("aarch64-darwin", "x86_64-linux"))
    parser.add_argument("--replica", type=int, choices=(1, 2, 3))
    arguments = parser.parse_args()
    root, report = arguments.root.resolve(), arguments.report.resolve()
    report.parent.mkdir(parents=True, exist_ok=True)
    if arguments.phase == "prepare":
        if None in (arguments.variant, arguments.scenario, arguments.system, arguments.replica):
            parser.error("prepare requires variant, scenario, system and replica")
        metadata = prepare(root, arguments.variant, arguments.scenario, arguments.system, arguments.replica)
        report.write_text(json.dumps(metadata, indent=2) + "\n")
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
            output.write(f"key={metadata['cache_key']}\nprefix={metadata['cache_prefix']}\n")
    else:
        execute(root, report)


if __name__ == "__main__":
    main()
