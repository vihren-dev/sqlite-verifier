"""Review one commit with the other agent tool, against `docs/review-checklist.md`.

A commit written in a Claude Code session is reviewed by Codex, and a commit
written in a Codex session by Claude Code. The reviewer gets only the commit, the
checklist and read access to the repository, not the author's reasoning. See
`plans/20261006-review-process.task.md`.
"""

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Literal

ROOT = Path(__file__).resolve().parents[1]
CHECKLIST = ROOT / "docs" / "review-checklist.md"
Reviewer = Literal["claude", "codex"]

#: The variable that marks a running review; a review started inside it stops.
GUARD = "SQLITE_VERIFIER_REVIEW"
#: Session markers that identify the calling tool. They are not documented
#: interfaces of either tool, so a missing marker must never select a reviewer silently.
CALLER_MARKERS: Mapping[Reviewer, str] = {"claude": "CLAUDECODE", "codex": "CODEX_THREAD_ID"}
#: Configuration that a marker prefix also matches but that a reviewer may need.
KEPT_CONFIGURATION = frozenset({"CODEX_HOME", "CLAUDE_CONFIG_DIR"})
#: Tools a Claude Code reviewer may use: reading files and showing commits only.
CLAUDE_READ_ONLY_TOOLS = ("Read", "Grep", "Glob", "Bash(jj show:*)", "Bash(jj diff:*)",
                          "Bash(jj log:*)", "Bash(git show:*)")
#: Wall-clock limit for one review.
REVIEW_TIMEOUT_SECONDS = 1200

FINDING = re.compile(r"^\s*[-*]\s*(R\d+)\s+(must|should)\s+(\S+?):(\d+)\b", re.MULTILINE)
NO_FINDINGS = re.compile(r"^\s*No findings\.\s*$", re.MULTILINE)


class UsageError(Exception):
    """A request that cannot be reviewed as given (exit code 2)."""


@dataclass(frozen=True)
class Review:
    """The findings that a review output contains, and whether it is well formed."""

    must: int
    should: int
    well_formed: bool


def select_reviewer(environment: Mapping[str, str]) -> Reviewer:
    """The reviewer for this caller: `REVIEWER` if set, otherwise the tool that did not call.

    A person in a terminal (no markers) gets Codex. Markers of both tools mean that
    one tool started the other, and the caller cannot be known; then `REVIEWER` is
    required.
    """
    requested = environment.get("REVIEWER", "")
    if requested:
        if requested not in ("claude", "codex"):
            raise UsageError(f"unknown reviewer {requested!r}; use REVIEWER=claude or REVIEWER=codex")
        return "claude" if requested == "claude" else "codex"
    callers = [tool for tool, marker in CALLER_MARKERS.items() if environment.get(marker)]
    if len(callers) > 1:
        raise UsageError("started from both Claude Code and Codex; set REVIEWER=claude or REVIEWER=codex")
    if callers == ["codex"]:
        return "claude"
    return "codex"


def is_session_marker(name: str) -> bool:
    """Whether `name` is a session variable of either tool, which a reviewer must not inherit."""
    if name in KEPT_CONFIGURATION:
        return False
    return (name in ("CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT", "AI_AGENT")
            or name.startswith(("CLAUDE_CODE_", "CODEX_")))


def reviewer_environment(environment: Mapping[str, str]) -> dict[str, str]:
    """The caller's environment without session markers, with the recursion guard set."""
    clean = {name: value for name, value in environment.items() if not is_session_marker(name)}
    clean[GUARD] = "1"
    return clean


def reviewer_command(reviewer: Reviewer) -> list[str]:
    """The command line of one review; the instructions, with the commit, arrive on standard input."""
    if reviewer == "codex":
        # `codex review --commit` rejects custom instructions, so the review runs as a
        # read-only `codex exec` session that is told which commit to review.
        return ["codex", "exec", "--sandbox", "read-only", "--ephemeral", "-"]
    return ["claude", "-p", "--allowedTools", *CLAUDE_READ_ONLY_TOOLS]


def instructions(checklist: str, revision: str, commit: str) -> str:
    """The reviewer's instructions: which commit to review, then the checklist."""
    return (f"Review the changes introduced by commit {commit} (jj revision {revision}; "
            f"`git show {commit}` shows it). Follow the checklist below exactly, "
            f"including its output format. Do not change any file.\n\n{checklist}")


def parse_review(output: str) -> Review:
    """Count findings by severity; output with neither findings nor `No findings.` is malformed."""
    severities = [match.group(2) for match in FINDING.finditer(output)]
    return Review(must=severities.count("must"), should=severities.count("should"),
                  well_formed=bool(severities) or bool(NO_FINDINGS.search(output)))


def exit_code(review: Review) -> int:
    """0 without "must" findings, 1 with them, 3 for output that cannot be trusted."""
    if not review.well_formed:
        return 3
    return 1 if review.must else 0


def resolve_commit(revision: str) -> str:
    """The git commit hash of a jj revision."""
    result = subprocess.run(["jj", "log", "-r", revision, "--no-graph", "-T", "commit_id"],
                            cwd=ROOT, capture_output=True, text=True, timeout=30, check=False)
    commit = result.stdout.strip()
    if result.returncode or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise UsageError(f"cannot resolve revision {revision!r}: {result.stderr.strip()}")
    return commit


def main(arguments: Sequence[str]) -> int:
    """Run one review and print it, followed by a one-line summary."""
    parser = argparse.ArgumentParser(prog="just review", description=__doc__)
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
    text = instructions(CHECKLIST.read_text(encoding="utf-8"), options.revision, commit)
    try:
        result = subprocess.run(reviewer_command(reviewer), cwd=ROOT, input=text, capture_output=True,
                                text=True, timeout=REVIEW_TIMEOUT_SECONDS, env=reviewer_environment(os.environ),
                                check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"review: {reviewer} did not complete: {error}", file=sys.stderr)
        return 3
    print(result.stdout, end="")
    review = parse_review(result.stdout) if result.returncode == 0 else Review(0, 0, False)
    if result.returncode:
        print(f"review: {reviewer} exited with {result.returncode}: {result.stderr.strip()}", file=sys.stderr)
    print(f"review: reviewer={reviewer} commit={commit} must={review.must} should={review.should} "
          f"well_formed={review.well_formed}", file=sys.stderr)
    return exit_code(review)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
