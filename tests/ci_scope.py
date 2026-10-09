"""Choose the smallest complete CI check set; unknown changes still run verifier checks.

Scopes, from smallest to largest:

- `docs`: Markdown documentation and the review log only; link checks without a build.
- `test`: every Nix test target and the host source tests.
- `infrastructure`: `test`, plus the host Nix tests (`just test-nix`), for changes to
  build definitions or shared test infrastructure.
- `packaging`: `test`, plus the installed-archive acceptance (`just runtime-package`),
  for changes to what the archive contains or how it installs.
- `package`: every check (`just package`). Pushes to `main`, release tags, manual runs
  and scheduled runs use it, and so do changes that are both infrastructure and
  packaging changes.
"""

import json
import os
from pathlib import Path
import re
import subprocess
from collections.abc import Sequence

FULL_EVENTS = {"workflow_dispatch", "schedule"}
"""Events that always run every check on both platforms."""

INFRASTRUCTURE_PREFIXES = ("build-support/", "nix/", "parser/", ".github/")
INFRASTRUCTURE_FILES = {"justfile", ".envrc", "flake.nix", "flake.lock", "lean-toolchain",
                        "lakefile.toml", "lake-manifest.json", "pytest.ini", "conftest.py",
                        "tools/ci_checks.py", "tools/check_resources.py",
                        "tests/nix_suites.json", "tests/conformance_frontend.json",
                        "tests/test_source_identity.py", "tests/test_nix_test_targets.py",
                        "tests/environment_snapshot_test.py", "tests/test_runtime_package.py",
                        "tests/test_test_ownership.py"}
"""Build definitions and shared test infrastructure, which `just test-nix` checks."""

PACKAGING_PREFIXES = ("packaging/", "bin/", "parser/", "nix/", ".github/")
PACKAGING_FILES = {"build-support/runtime.nix", "build-support/default.nix", "build-support/sources.nix",
                   "build-support/lean-toolchain.nix", "build-support/lean4export.nix",
                   "lean-toolchain", "lakefile.toml", "lake-manifest.json", "justfile",
                   "migration_check/runtime.py", "docs/install.md", "ProofChecker.lean",
                   "tests/runtime_package_test.py", "tests/runtime_installation.py",
                   "tests/test_toolchain_smoke.py"}
"""Archive contents, installation and runtime discovery, which the installed acceptance checks."""


def is_shared_test_helper(path: str) -> bool:
    """A Python file under tests/ that is not a test module, such as a fixture module.

    Many suites import such helpers, so a change to one selects the host Nix tests,
    which check the Nix target inputs and their invalidation.
    """
    name = Path(path).name
    return (path.startswith("tests/") and path.endswith(".py")
            and not name.startswith("test_") and not name.endswith("_test.py"))


RECORD_FILES = frozenset({"reviews/log.jsonl"})
"""Records that no build or test reads. CI checks the review log in every scope
(`tools/review_log_check.py`), so a change to it alone needs no build."""


def is_documentation(path: str) -> bool:
    """Markdown at the top level or under docs/, plans/ or examples/, except installation docs.

    No build reads these files, so a change of only such files needs only the link checks.
    The installation guide ships in the runtime archive and is excluded.
    """
    return (path.endswith(".md") and path not in PACKAGING_FILES
            and ("/" not in path or path.startswith(("docs/", "plans/", "examples/"))))


def scope(paths: Sequence[str], event: str, ref: str) -> str:
    """Select the scope for the changed paths; the module docstring describes each scope."""
    if event in FULL_EVENTS or ref.startswith("refs/tags/") or not paths:
        return "package"
    if all(is_documentation(path) or path in RECORD_FILES for path in paths):
        return "docs"
    if event == "push":
        return "package"
    infrastructure = any(path in INFRASTRUCTURE_FILES or path.startswith(INFRASTRUCTURE_PREFIXES)
                         or is_shared_test_helper(path) for path in paths)
    packaging = any(path in PACKAGING_FILES or path.startswith(PACKAGING_PREFIXES) for path in paths)
    if infrastructure and packaging:
        return "package"
    if infrastructure:
        return "infrastructure"
    if packaging:
        return "packaging"
    return "test"


def main() -> None:
    """Read a bounded Git diff without interpolating event data into shell commands."""
    event = os.environ["GITHUB_EVENT_NAME"]
    ref = os.environ["GITHUB_REF"]
    payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    base = payload.get("pull_request", {}).get("base", {}).get("sha") if event == "pull_request" else payload.get("before")
    paths: list[str] = []
    if event not in FULL_EVENTS and not ref.startswith("refs/tags/"):
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
