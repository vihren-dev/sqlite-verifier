"""Choose the smallest complete CI check set; unknown changes still run verifier checks."""

import json
import os
from pathlib import Path
import re
import subprocess
from collections.abc import Sequence

PACKAGE_PREFIXES = ("packaging/", "migration_check/", "parser/", "bin/", "nix/", "tools/",
                    "examples/", ".github/")
PACKAGE_FILES = {"justfile", ".envrc", "flake.nix", "flake.lock", "lean-toolchain",
                 "lakefile.toml", "lake-manifest.json", "ProofChecker.lean",
                 "tests/runtime_package_test.py", "tests/toolchain_smoke.py"}


def scope(paths: Sequence[str], event: str, ref: str) -> str:
    """Release/manual runs package; docs skip builds; runtime infrastructure changes package."""
    if event == "workflow_dispatch" or ref.startswith("refs/tags/") or not paths:
        return "package"
    if all(path.endswith(".md") and ("/" not in path or path.startswith(("docs/", "plans/", "examples/")))
           for path in paths):
        return "docs"
    if any(path in PACKAGE_FILES or path.startswith(PACKAGE_PREFIXES) for path in paths):
        return "package"
    return "check"


def main() -> None:
    """Read a bounded Git diff without interpolating event data into shell commands."""
    event = os.environ["GITHUB_EVENT_NAME"]
    ref = os.environ["GITHUB_REF"]
    payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    base = payload.get("pull_request", {}).get("base", {}).get("sha") if event == "pull_request" else payload.get("before")
    paths: list[str] = []
    if event != "workflow_dispatch" and not ref.startswith("refs/tags/"):
        if not isinstance(base, str) or re.fullmatch(r"[0-9a-f]{40}", base) is None:
            raise ValueError("CI change selection requires a complete base commit hash")
        if base != "0" * 40:
            result = subprocess.run(["git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD"],
                                    check=True, capture_output=True, timeout=30)
            paths = [path.decode("utf-8", "surrogateescape") for path in result.stdout.split(b"\0") if path]
    selected = scope(paths, event, ref)
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"scope={selected}\n")
    print(f"CI scope: {selected}; changed paths: {len(paths)}")


if __name__ == "__main__":
    main()
