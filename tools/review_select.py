"""Pure decisions of `just review`: which tool reviews, with which environment and command.

The imperative part (running `jj` and the reviewer, writing the log) is in
`tools/review.py`. See `plans/20261006-review-process.task.md`.
"""

from collections.abc import Mapping, Sequence
import re
from typing import Literal

Reviewer = Literal["claude", "codex"]

#: The variable that marks a running review; a review started inside it stops.
GUARD = "SQLITE_VERIFIER_REVIEW"
#: Session markers that identify the calling tool. They are not documented
#: interfaces of either tool, so a missing marker must never select a reviewer silently.
CALLER_MARKERS: Mapping[Reviewer, str] = {"claude": "CLAUDECODE", "codex": "CODEX_THREAD_ID"}
#: Session variables of either tool. A reviewer must not inherit them: they would make it
#: look like part of the caller's session, and they would make a nested caller ambiguous.
SESSION_MARKER_NAMES = frozenset({"CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT", "AI_AGENT"})
SESSION_MARKER_PREFIXES = ("CLAUDE_CODE_", "CODEX_")
#: Configuration that a marker prefix also matches but that a reviewer may need.
KEPT_CONFIGURATION = frozenset({"CODEX_HOME", "CLAUDE_CONFIG_DIR"})
#: Tools a Claude Code reviewer may use: reading files and showing commits only.
CLAUDE_READ_ONLY_TOOLS = ("Read", "Grep", "Glob", "Bash(jj show:*)", "Bash(jj diff:*)",
                          "Bash(jj log:*)", "Bash(git show:*)")
#: A complete option in help text, such as `-p` or `--allowedTools`, but not `-p` inside `--print`.
OPTION_TOKEN = re.compile(r"(?<![\w-])--?[A-Za-z][\w-]*")


class UsageError(Exception):
    """A request that cannot be reviewed as given (exit code 2)."""


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
    caller = caller_tool(environment)
    if caller == "both":
        raise UsageError("started from both Claude Code and Codex; set REVIEWER=claude or REVIEWER=codex")
    return "claude" if caller == "codex" else "codex"


def is_session_marker(name: str) -> bool:
    """Whether `name` is a session variable of either tool, which a reviewer must not inherit."""
    if name in KEPT_CONFIGURATION:
        return False
    return name in SESSION_MARKER_NAMES or name.startswith(SESSION_MARKER_PREFIXES)


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


def missing_options(command: Sequence[str], help_text: str) -> list[str]:
    """The options of `command` that `help_text` does not mention.

    Used to check that an installed CLI still has the options of the reviewer command,
    because some CLIs ignore unknown options when `--help` is given.
    """
    listed = set(OPTION_TOKEN.findall(help_text))
    return [part for part in command if part.startswith("-") and part != "-" and part not in listed]


def instructions(checklist: str, revision: str, commit: str) -> str:
    """The reviewer's instructions: which commit to review, then the checklist."""
    return (f"Review the changes introduced by commit {commit} (jj revision {revision}; "
            f"`git show {commit}` shows it). Follow the checklist below exactly, "
            f"including its output format. Do not change any file.\n\n{checklist}")


def caller_tool(environment: Mapping[str, str]) -> str:
    """The tool that started the review: "claude", "codex", "both", or "person" (no markers)."""
    callers = [tool for tool, marker in CALLER_MARKERS.items() if environment.get(marker)]
    return "both" if len(callers) > 1 else callers[0] if callers else "person"
