"""Review one commit with the other agent tool, against `docs/review-checklist.md`.

A commit written in a Claude Code session is reviewed by Codex, and a commit
written in a Codex session by Claude Code. The reviewer gets only the commit, the
checklist and read access to the repository, not the author's reasoning. Each review
is added to the review log (`tools/review_log.py`) for later statistics. See
`plans/20261006-review-process.task.md`.
"""

import argparse
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
import os
import re
import subprocess
import sys

from tools.review_log import CHECKLIST, ROOT, append, log_path, parse_findings, record_findings, review_record
from tools.review_select import (GUARD, Reviewer, UsageError, caller_tool, instructions, reviewer_command,
                                 reviewer_environment, select_reviewer)

#: Wall-clock limit for one review. A real review took about one minute in testing.
REVIEW_TIMEOUT_SECONDS = 1200
#: Wall-clock limit for one `jj` query, a local and fast operation.
JJ_TIMEOUT_SECONDS = 30


@dataclass(frozen=True)
class Review:
    """The findings that a review output contains, and whether it is well formed."""

    must: int
    should: int
    well_formed: bool


def parse_review(output: str) -> Review:
    """Count findings by severity; output with neither findings nor `No findings.` is malformed."""
    findings, well_formed = parse_findings(output)
    severities = [finding.severity for finding in findings]
    return Review(must=severities.count("must"), should=severities.count("should"), well_formed=well_formed)


def exit_code(review: Review) -> int:
    """0 without "must" findings, 1 with them, 3 for output that cannot be trusted."""
    if not review.well_formed:
        return 3
    return 1 if review.must else 0


def jj(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Run one `jj` query in the repository."""
    return subprocess.run(["jj", *arguments], cwd=ROOT, capture_output=True, text=True,
                          timeout=JJ_TIMEOUT_SECONDS, check=False)


def resolve_commit(revision: str) -> str:
    """The git commit hash of a jj revision.

    The reviewer reads the commit with `git show` or `jj show`, and the summary line
    names it. A hash stays valid if the working copy moves while the review runs.
    """
    result = jj("log", "-r", revision, "--no-graph", "-T", "commit_id")
    commit = result.stdout.strip()
    if result.returncode or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise UsageError(f"cannot resolve revision {revision!r}: {result.stderr.strip()}")
    return commit


def changed_files(commit: str) -> list[str]:
    """The files that a commit changes; the statistics use them to see which conditions could fire."""
    result = jj("diff", "-r", commit, "--name-only")
    return [line for line in result.stdout.splitlines() if line.strip()] if result.returncode == 0 else []


def run_reviewer(reviewer: Reviewer, text: str) -> tuple[str, Review]:
    """The reviewer's output and its parsed review; a failed run is not well formed."""
    try:
        result = subprocess.run(reviewer_command(reviewer), cwd=ROOT,
                                input=text, capture_output=True, text=True, timeout=REVIEW_TIMEOUT_SECONDS,
                                env=reviewer_environment(os.environ), check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"review: {reviewer} did not complete: {error}. Check that `{reviewer}` is installed and "
              f"logged in, then run the review again, or choose the other reviewer with REVIEWER=.",
              file=sys.stderr)
        return "", Review(0, 0, False)
    if result.returncode:
        print(f"review: {reviewer} exited with {result.returncode}: {result.stderr.strip()}", file=sys.stderr)
        return result.stdout, Review(0, 0, False)
    return result.stdout, parse_review(result.stdout)


def main(arguments: Sequence[str]) -> int:
    """Run one review, print it with the ids of its findings, and add it to the review log."""
    parser = argparse.ArgumentParser(prog="just review", description=main.__doc__)
    parser.add_argument("revision", nargs="?", default="@-", help="jj revision to review (default: @-)")
    options = parser.parse_args(arguments)
    try:
        if os.environ.get(GUARD):
            raise UsageError("already inside a review; a reviewer must not start another review")
        reviewer = select_reviewer(os.environ)
        commit = resolve_commit(options.revision)
    except UsageError as error:
        print(f"review: {error}", file=sys.stderr)
        return 2
    checklist = CHECKLIST.read_text(encoding="utf-8")
    output, review = run_reviewer(reviewer, instructions(checklist, options.revision, commit))
    print(output, end="")
    code = exit_code(review)
    record = review_record(commit=commit, revision=options.revision, reviewer=reviewer,
                           caller=caller_tool(os.environ), files=changed_files(commit), checklist=checklist,
                           exit_code=code, output=output if review.well_formed else "",
                           when=datetime.now(timezone.utc))
    append(record, log_path())
    for finding in record_findings(record):
        print(f"review: finding {finding['id']} {finding['rule']} {finding['severity']} "
              f"{finding['path']}:{finding['line']}", file=sys.stderr)
    print(f"review: reviewer={reviewer} commit={commit} must={review.must} should={review.should} "
          f"well_formed={review.well_formed} logged={record['id']}", file=sys.stderr)
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
