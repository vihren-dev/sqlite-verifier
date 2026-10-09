"""Remove Nix store paths that the current commit does not need, before CI saves its cache.

CI restores the whole Nix store from the GitHub Actions cache and saves it again after
the checks. Without garbage collection, each commit adds new runtime and test outputs
and keeps all older ones: the Linux cache grew to 5.8 GB, while one commit needs about
1.4 GB (compressed). GitHub keeps at most 10 GB of caches for a repository, so the
platform caches evicted each other.

The tool adds garbage-collector roots for what the next run needs, then collects
everything else:

- the test targets, runtimes, parsers, parser library checks and core and base API
  references, as derivations; with
  `keep-outputs` in the Nix configuration, the outputs of all their build inputs stay too;
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
TARGETS = ["tests", "runtime", "conformance", "parsers", "parserLibrary", "apiReferenceCore",
           "apiReferenceBase"]
"""Attributes of build-support/default.nix whose build closures the next run needs. The core API
reference depends only on the toolchain and doc-gen4; the base has no commit in it. So later
commits reuse the core, and commits with the same Lean sources also reuse the base. The parser
library checks, with the sanitizer job, rerun only when the parser sources or corpora change."""
ROOT_TIMEOUT_SECONDS = 600
"""Evaluating the targets or entering the development shell; both are cached after the checks."""
FLAKE_TIMEOUT_SECONDS = 300
"""Listing or realising flake inputs, which are already in the store after the checks."""
COLLECT_TIMEOUT_SECONDS = 900
"""Deleting the unrooted paths of a restored store of several gigabytes."""


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
    """The store paths of the flake source and all its inputs, from `nix flake archive --json`.

    These paths become roots, so garbage collection keeps the pinned nixpkgs source that
    the next run needs to evaluate the project, instead of downloading it again.
    """
    pending, paths = [json.loads(archive_json)], []
    while pending:
        node = pending.pop()
        if isinstance(node.get("path"), str):
            paths.append(node["path"])
        pending.extend(node.get("inputs", {}).values())
    return paths


BEFORE_COLLECTION = ("No store paths were removed. The cache is saved without garbage collection; "
                     "fix the command and run the workflow again to shrink it.")
"""What a failure means while roots are registered: the store is unchanged."""
DURING_COLLECTION = ("Garbage collection stopped early: some unneeded paths may remain, so the saved "
                     "cache can be larger. Every rooted path is kept. Correct the cause in the Nix "
                     "error above and run the workflow again to shrink the cache.")
"""What a failure of `nix-store --gc` itself means: the collection may be incomplete."""


def run(command: list[str], timeout: float, consequence: str = BEFORE_COLLECTION) -> str:
    """Run one Nix command; a failure stops the tool so that nothing is collected without roots."""
    print("+", " ".join(command), flush=True)
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.CalledProcessError as error:
        print(f"Command failed with exit code {error.returncode}: {' '.join(command)}\n"
              f"{(error.stderr or '').strip()}\n{consequence}", file=sys.stderr, flush=True)
        raise
    except subprocess.TimeoutExpired as error:
        stderr = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else error.stderr
        print(f"Command exceeded {timeout:g} seconds: {' '.join(command)}\n"
              f"{(stderr or '').strip()}\n{consequence}", file=sys.stderr, flush=True)
        raise
    if result.stderr.strip():
        print(result.stderr.strip().splitlines()[-1], flush=True)
    return result.stdout


def main() -> None:
    """Register all roots first; collect garbage only after every root exists."""
    ROOTS.mkdir(parents=True, exist_ok=True)
    for command in root_commands(ROOTS):
        run(command, timeout=ROOT_TIMEOUT_SECONDS)
    archive = run(["nix", *FLAGS, "flake", "archive", "--json", "path:./nix"], timeout=FLAKE_TIMEOUT_SECONDS)
    for index, path in enumerate(flake_input_paths(archive)):
        run(["nix-store", "--add-root", str(ROOTS / f"flake-input-{index}"), "--indirect",
             "--realise", path], timeout=FLAKE_TIMEOUT_SECONDS)
    run(["nix-store", "--gc"], timeout=COLLECT_TIMEOUT_SECONDS, consequence=DURING_COLLECTION)


if __name__ == "__main__":
    sys.exit(main())
