"""Check that the review log only grows: each line is a record, and no base line is lost.

`AGENTS.md` forbids editing or deleting lines of `reviews/log.jsonl`. CI runs this check in
every scope, so a pull request that changes only documentation and the log can skip the
build, and still cannot change or remove a review record. Merges of main into a branch
reorder lines and can remove a line that both sides contain, so the check requires each
base line to be present, not a position or a count.
"""

import argparse
from collections.abc import Sequence
import json
import os
from pathlib import Path
import re
import subprocess
import sys

LOG = "reviews/log.jsonl"
"""The log path, relative to the repository root."""
REQUIRED_FIELDS = {"review": frozenset({"kind", "id", "commit", "date", "findings", "well_formed"}),
                   "resolution": frozenset({"kind", "finding", "outcome", "date"})}
"""The fields of each record kind, as `tools/review.py` and `tools/review_log.py` write them."""
BASE_VARIABLE = "REVIEW_LOG_BASE"
"""The base commit hash; CI sets it from the event, without passing event data to a shell."""
NO_BASE = "0" * 40
"""Git's hash for a missing commit, which GitHub sends for a new branch."""
GIT_TIMEOUT_SECONDS = 30
"""Reading one file from a local commit."""


def record_problem(line: str) -> str | None:
    """Why one log line is not a review record, or `None` when it is one."""
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        return "not JSON"
    if not isinstance(record, dict):
        return "not a JSON object"
    kind = record.get("kind")
    required = REQUIRED_FIELDS.get(kind) if isinstance(kind, str) else None
    if required is None:
        return f"unknown record kind {kind!r}"
    missing = sorted(required - record.keys())
    return f"missing fields {', '.join(missing)}" if missing else None


def problems(base: Sequence[str], head: Sequence[str]) -> list[str]:
    """The violations of the append-only rule from the base log to the head log.

    Each head line must be a record, and each base line must occur in the head log unchanged.
    The rule requires nothing about the order of lines or about repeated lines.
    """
    found = [f"line {number}: {problem}" for number, line in enumerate(head, start=1)
             if (problem := record_problem(line)) is not None]
    present = set(head)
    found += [f"base line {number} is changed or removed" for number, line in enumerate(base, start=1)
              if line not in present]
    return found


def base_lines(root: Path, base: str) -> list[str]:
    """The log lines of the base commit; a commit without the log has none."""
    if re.fullmatch(r"[0-9a-f]{40}", base) is None:
        raise ValueError(f"{BASE_VARIABLE} must be a full commit hash, not {base!r}")
    if base == NO_BASE:
        return []
    listed = subprocess.run(["git", "ls-tree", "--name-only", base, LOG], cwd=root, check=True,
                            capture_output=True, text=True, timeout=GIT_TIMEOUT_SECONDS)
    if not listed.stdout.strip():
        return []
    shown = subprocess.run(["git", "show", f"{base}:{LOG}"], cwd=root, check=True,
                           capture_output=True, text=True, timeout=GIT_TIMEOUT_SECONDS)
    return shown.stdout.splitlines()


def main(arguments: Sequence[str]) -> int:
    """Check the working-tree log against the base commit in `REVIEW_LOG_BASE`, when it is set."""
    parser = argparse.ArgumentParser(description=main.__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    options = parser.parse_args(arguments)
    log = options.root / LOG
    head = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
    base = os.environ.get(BASE_VARIABLE, "")
    found = problems(base_lines(options.root, base) if base else [], head)
    for problem in found:
        print(f"review log: {LOG}: {problem}; restore the original line and add new records "
              f"only at the end", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
