"""Remove Nix store paths that the current commit does not need, before CI saves its cache.

CI restores the whole Nix store from the GitHub Actions cache and saves it again after
the checks. Without garbage collection, each commit adds new runtime and test outputs
and keeps all older ones: the Linux cache grew to 5.8 GB, while one commit needs about
1.4 GB (compressed). GitHub keeps at most 10 GB of caches for a repository, so the
platform caches evicted each other.

The tool adds garbage-collector roots for what the next run needs, then collects
everything else:

- the test targets, runtimes and parsers, as derivations; with `keep-outputs` in the
  Nix configuration, the outputs of all their build inputs stay too;
- the development shell, as a profile;
- the flake inputs, which include the pinned nixpkgs source used for evaluation.

A path removed by mistake costs a rebuild or a download in a later run. It cannot
change a result, because Nix reuses a path only when its hash matches.
"""

import json
from pathlib import Path
import subprocess
import sys

ROOTS = Path("build/gc-roots")
FLAGS = ["--extra-experimental-features", "nix-command flakes"]
TARGETS = ["tests", "runtime", "conformance", "parsers"]
"""Attributes of build-support/default.nix whose build closures the next run needs."""


def root_commands(roots: Path) -> list[list[str]]:
    """Commands that register the roots of the current commit's build closure."""
    instantiate = ["nix-instantiate", "build-support/default.nix", *FLAGS,
                   "--add-root", str(roots / "derivation"), "--indirect"]
    for target in TARGETS:
        instantiate += ["-A", target]
    shell = ["nix", *FLAGS, "develop", "path:./nix", "--profile", str(roots / "dev-shell"),
             "--command", "true"]
    return [instantiate, shell]


def flake_input_paths(archive_json: str) -> list[str]:
    """The store paths of the flake source and all its inputs, from `nix flake archive --json`."""
    pending, paths = [json.loads(archive_json)], []
    while pending:
        node = pending.pop()
        if isinstance(node.get("path"), str):
            paths.append(node["path"])
        pending.extend(node.get("inputs", {}).values())
    return paths


def run(command: list[str], timeout: float) -> str:
    """Run one Nix command; a failure stops the tool so that nothing is collected without roots."""
    print("+", " ".join(command), flush=True)
    result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)
    if result.stderr.strip():
        print(result.stderr.strip().splitlines()[-1], flush=True)
    return result.stdout


def main() -> None:
    """Register all roots first; collect garbage only after every root exists."""
    ROOTS.mkdir(parents=True, exist_ok=True)
    for command in root_commands(ROOTS):
        run(command, timeout=600)
    archive = run(["nix", *FLAGS, "flake", "archive", "--json", "path:./nix"], timeout=300)
    for index, path in enumerate(flake_input_paths(archive)):
        run(["nix-store", "--add-root", str(ROOTS / f"flake-input-{index}"), "--indirect",
             "--realise", path], timeout=300)
    run(["nix-store", "--gc"], timeout=900)


if __name__ == "__main__":
    sys.exit(main())
