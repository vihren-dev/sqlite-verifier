"""Check approved example sources using target-branch code and immutable Git objects."""

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

APPROVED_ROOTS = ("examples/approved", "examples/allowed_failure/approved")


def git(repository: Path, *arguments: str) -> bytes:
    """Read local Git objects without running project code or replacement objects."""
    return subprocess.run(["git", "--no-replace-objects", "-C", str(repository), *arguments],
                          check=True, capture_output=True, timeout=10).stdout


def blob(repository: Path, revision: str, path: str) -> bytes:
    """Read one object at a validated immutable revision, never through the filesystem."""
    return git(repository, "show", f"{revision}:{path}")


def source_hashes(repository: Path, revision: str, root: str) -> dict[str, str]:
    """Hash every regular Lean source in the protected directory, including helpers."""
    result: dict[str, str] = {}
    for record in git(repository, "ls-tree", "-rz", revision, "--", root).split(b"\0"):
        if not record:
            continue
        metadata, filename = record.split(b"\t", 1)
        mode, kind, _ = metadata.split()
        name = filename.decode("utf-8")
        if not name.endswith(".lean"):
            continue
        if mode not in (b"100644", b"100755") or kind != b"blob":
            raise ValueError(f"Approved source must be a regular Git file: {name}")
        relative = name.removeprefix(root + "/")
        result[f"approved/{relative}"] = hashlib.sha256(blob(repository, revision, name)).hexdigest()
    return result


def check(repository: Path, base: str, head: str) -> None:
    """Reject self-approved manifest changes and any changed, added or missing source."""
    if any(re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", revision) is None
           for revision in (base, head)):
        raise ValueError("Base and head must be complete lowercase Git commit hashes")
    for root in APPROVED_ROOTS:
        path = f"{root}/baseline.json"
        trusted = blob(repository, base, path)
        if blob(repository, head, path) != trusted:
            raise ValueError(f"Protected baseline changed: {path}; explicit owner review required")
        expected: object = json.loads(trusted)
        if not isinstance(expected, dict) or not {
            "approved/Requirements.lean", "approved/Interpretation.lean"
        } <= expected.keys() or any(not isinstance(name, str) or not name.startswith("approved/")
                                   or not isinstance(digest, str)
                                   or re.fullmatch(r"[0-9a-f]{64}", digest) is None
                                   for name, digest in expected.items()):
            raise ValueError(f"Invalid target-branch baseline: {path}")
        actual = source_hashes(repository, head, root)
        changed = sorted(name for name in expected.keys() | actual.keys()
                         if expected.get(name) != actual.get(name))
        if changed:
            raise ValueError(f"Protected approved sources changed in {root}: {', '.join(changed)}")


def main() -> None:
    """Accept only CI-supplied commit identities; no candidate executable is invoked."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    arguments = parser.parse_args()
    check(arguments.repository, arguments.base, arguments.head)
    print("Protected approved-source baselines match the target branch.")


if __name__ == "__main__":
    main()
