"""Check the CI seed flow: build once, `lake cache stage`, then `unstage` into an empty cache.

Usage: python3 experiments/lake-cache/seed_flow.py WORK_DIR

Run setup_shim.py WORK_DIR first. A Nix seed step would do the first part (build each
example workspace with `lake build -o MAPPINGS` and stage the outputs); each test
target would do the second part (unstage into its own cache inside a generated
workspace). The script prints how many modules each later build compiled.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lake_bench as bench  # noqa: E402  (reads WORK_DIR from sys.argv[1])

LAKE_BIN = (bench.ROOT / "build/runtime/lean/bin").resolve()
"""Pinned toolchain whose `lake` runs every step."""


def lake(arguments: list[str], directory: Path, cache: Path) -> str:
    """Run one Lake command with the given cache; stop with Lake's output when it fails."""
    environment = {**os.environ, "LAKE_CACHE_DIR": str(cache), "PATH": f"{LAKE_BIN}{os.pathsep}{os.environ['PATH']}"}
    result = subprocess.run(["lake", *arguments], cwd=directory, env=environment, capture_output=True, text=True,
                            timeout=bench.BUILD_TIMEOUT_SECONDS)
    if result.returncode:
        tail = bench.FAILURE_TAIL_CHARACTERS
        raise SystemExit(f"lake {' '.join(arguments)} failed in {directory}:\n{result.stdout[-tail:]}"
                         f"{result.stderr[-tail:]}\nCorrect the reported error, then run the script again.")
    return result.stdout


def compiled(output: str) -> int:
    """Workspace modules that Lake compiled; library modules are only replayed."""
    return sum(1 for line in output.splitlines() if "Built " in line and "Belay" not in line)


def main() -> None:
    """Seed with both examples, move the seed into an empty cache, and build fresh workspaces on it."""
    seed_cache, test_cache, staged = bench.WORK / "seed-cache", bench.WORK / "test-cache", bench.WORK / "seed-staged"
    for directory in (seed_cache, test_cache, staged):
        shutil.rmtree(directory, ignore_errors=True)
    for case in bench.CASES:
        workspace = bench.workspace(bench.WORK / f"bench/seed-{case}", case, bench.WORK / "shim")
        print(case, "seed build compiled", compiled(lake(["build", "-o", "mappings.jsonl"], workspace, seed_cache)))
        lake(["cache", "stage", "mappings.jsonl", str(staged / case)], workspace, seed_cache)
    for case in bench.CASES:
        # `unstage` writes mappings for the root package, so it runs inside a generated workspace.
        workspace = bench.workspace(bench.WORK / f"bench/unstage-{case}", case, bench.WORK / "shim")
        lake(["cache", "unstage", str(staged / case)], workspace, test_cache)
    for case in bench.CASES:
        workspace = bench.workspace(bench.WORK / f"bench/use-{case}", case, bench.WORK / "shim")
        print(case, "fresh workspace on unstaged cache compiled", compiled(lake(["build"], workspace, test_cache)))
    edited = bench.workspace(bench.WORK / "bench/use-edit", "small", bench.WORK / "shim", "Proofs")
    print("small proof edit on unstaged cache compiled", compiled(lake(["build"], edited, test_cache)))


if __name__ == "__main__":
    main()
