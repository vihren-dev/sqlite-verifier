"""Time Lake-driven builds of generated verification workspaces with a shared artifact cache.

Usage: python3 experiments/lake-cache/lake_bench.py WORK_DIR TRIALS > results.jsonl

Run setup_shim.py WORK_DIR first. Each scenario builds in a fresh directory, like a
verifier run with a temporary workspace; the artifact cache is WORK_DIR/cache and
starts empty in each trial.
"""

import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build" / "lake-cache"
"""Directory prepared by setup_shim.py."""

CASES = {
    "small": (ROOT / "examples/approved", ROOT / "examples/add_column_then_table", WORK / "generated-small"),
    "atuin": (ROOT / "examples/atuin/approved", ROOT / "examples/atuin", WORK / "generated-atuin"),
}
"""Approved sources, candidate sources and generated sources of each example."""
CONTRACT_ONLY = ("SchemaInputs", "SqlInputs", "Requirements", "Interpretation")
"""Targets verify-bundle needs compiled; Lake builds their approved imports too."""


def workspace(directory: Path, case: str, shim: Path, edit: str | None = None) -> Path:
    """Generate a TOML-only workspace: approved, generated and candidate modules as one library."""
    approved, candidate, generated = CASES[case]
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir(parents=True)
    for source in [*approved.glob("*.lean"), *candidate.glob("*.lean"), *generated.glob("*.lean")]:
        shutil.copy(source, directory / source.name)
    if edit:
        with (directory / f"{edit}.lean").open("a") as stream:
            stream.write(f"\n-- edit {time.time_ns()}\n")
    roots = sorted(path.stem for path in directory.glob("*.lean"))
    (directory / "lakefile.toml").write_text(
        'name = "verification"\ndefaultTargets = ["Verification"]\n'
        "enableArtifactCache = true\nrestoreAllArtifacts = true\n"
        f'[[lean_lib]]\nname = "Verification"\nroots = {json.dumps(roots)}\n'
        f'[[require]]\nname = "sqliteVerifier"\npath = "{shim}"\n')
    shutil.copy(shim / "lean-toolchain", directory / "lean-toolchain")
    return directory


def build(directory: Path, targets: tuple[str, ...] = ()) -> tuple[float, int]:
    """Run `lake build`; return wall seconds and the number of modules Lake compiled."""
    started = time.perf_counter()
    environment = {**os.environ, "LAKE_CACHE_DIR": str(WORK / "cache"),
                   "PATH": f"{(ROOT / 'build/runtime/lean/bin').resolve()}{os.pathsep}{os.environ['PATH']}"}
    result = subprocess.run(["lake", "build", *targets], cwd=directory, capture_output=True, text=True,
                            timeout=600, env=environment)
    seconds = time.perf_counter() - started
    if result.returncode:
        raise SystemExit(f"lake build failed in {directory}:\n{result.stdout[-2000:]}{result.stderr[-2000:]}")
    return seconds, sum(1 for line in result.stdout.splitlines() if "Built " in line and "Belay" not in line)


def main(shim: Path, cache: Path, trials: int) -> None:
    """Run each scenario TRIALS times and print medians as JSON lines."""
    base = WORK / "bench"
    for case in CASES:
        samples: dict[str, list[tuple[float, int]]] = {}
        for trial in range(trials):
            shutil.rmtree(cache, ignore_errors=True)
            runs = [
                ("cold_empty_cache", lambda: build(workspace(base / "a", case, shim))),
                ("noop_same_dir", lambda: build(base / "a")),
                ("fresh_dir_warm_cache", lambda: build(workspace(base / "b", case, shim))),
                ("fresh_dir_proof_edit", lambda: build(workspace(base / "c", case, shim, "Proofs"))),
                ("fresh_dir_contract_only", lambda: build(workspace(base / "d", case, shim), CONTRACT_ONLY)),
            ]
            for name, run in runs:
                samples.setdefault(name, []).append(run())
        for name, values in samples.items():
            print(json.dumps({"case": case, "scenario": name,
                              "median_s": round(statistics.median(v[0] for v in values), 3),
                              "compiled": [v[1] for v in values]}), flush=True)


if __name__ == "__main__":
    main(WORK / "shim", WORK / "cache", int(sys.argv[2]))
