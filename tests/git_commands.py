"""Run Git in temporary test repositories that CI routing and review-log tests build."""

import subprocess
from pathlib import Path

GIT_TIMEOUT_SECONDS = 10
"""Bound each Git command; the test repositories hold only a few small files."""


def git(repository: Path, *arguments: str) -> bytes:
    """Run one Git command in a test repository and return its standard output."""
    return subprocess.run(["git", "--no-replace-objects", "-C", str(repository), *arguments],
                          check=True, capture_output=True, timeout=GIT_TIMEOUT_SECONDS).stdout
