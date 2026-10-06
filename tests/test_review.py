"""Reviewer selection, isolation and result parsing of `just review` (tools/review.py)."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

from tools.review import (GUARD, Review, UsageError, exit_code, missing_options, parse_review,
                          reviewer_command, reviewer_environment, select_reviewer)

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "review.py"
COMMIT = "0123456789abcdef0123456789abcdef01234567"


@pytest.mark.unit
@pytest.mark.parametrize("environment,expected", [
    ({"CLAUDECODE": "1"}, "codex"),
    ({"CODEX_THREAD_ID": "t"}, "claude"),
    ({}, "codex"),
    ({"CLAUDECODE": "1", "CODEX_THREAD_ID": "t", "REVIEWER": "claude"}, "claude"),
    ({"CODEX_THREAD_ID": "t", "REVIEWER": "codex"}, "codex"),
])
def test_select_reviewer(environment: dict[str, str], expected: str) -> None:
    """The other tool reviews; a person gets Codex; REVIEWER overrides detection."""
    assert select_reviewer(environment) == expected


@pytest.mark.unit
@pytest.mark.parametrize("environment,message", [
    ({"CLAUDECODE": "1", "CODEX_THREAD_ID": "t"}, "both"),
    ({"REVIEWER": "gemini"}, "unknown reviewer"),
])
def test_select_reviewer_rejects(environment: dict[str, str], message: str) -> None:
    """Markers of both tools, or an unknown reviewer, stop instead of guessing."""
    with pytest.raises(UsageError, match=message):
        select_reviewer(environment)


@pytest.mark.unit
def test_reviewer_environment_strips_session_markers() -> None:
    """Session markers of both tools go; configuration and credentials stay; the guard is set."""
    caller = {"CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "s", "CLAUDE_PID": "1", "AI_AGENT": "claude-code",
              "CODEX_THREAD_ID": "t", "CODEX_SANDBOX": "seatbelt", "CODEX_HOME": "/home/codex",
              "CLAUDE_CONFIG_DIR": "/home/claude", "PATH": "/bin", "OPENAI_API_KEY": "k"}
    assert reviewer_environment(caller) == {"CODEX_HOME": "/home/codex", "CLAUDE_CONFIG_DIR": "/home/claude",
                                            "PATH": "/bin", "OPENAI_API_KEY": "k", GUARD: "1"}


@pytest.mark.unit
def test_reviewer_commands_are_read_only() -> None:
    """Codex runs in its read-only sandbox; Claude Code gets only reading tools."""
    assert reviewer_command("codex") == ["codex", "exec", "--sandbox", "read-only", "--ephemeral", "-"]
    claude = reviewer_command("claude")
    assert claude[:3] == ["claude", "-p", "--allowedTools"]
    assert not any(tool.startswith(("Edit", "Write", "Bash(jj commit", "Bash(rm")) for tool in claude[3:])


@pytest.mark.unit
def test_missing_options() -> None:
    """An option that the help text does not mention is reported; values and `-` are not options."""
    help_text = "Usage: claude [options]\n  -p, --print\n  --allowedTools <tools...>\n"
    assert missing_options(["claude", "-p", "--allowedTools", "Read", "-"], help_text) == []
    assert missing_options(["claude", "-p", "--allowedToolz", "Read"], help_text) == ["--allowedToolz"]
    assert missing_options(["claude", "-p"], "Usage: claude [options]\n  --print\n") == ["-p"]


@pytest.mark.integration
@pytest.mark.parametrize("reviewer", ["codex", "claude"])
def test_installed_cli_has_reviewer_options(reviewer: str) -> None:
    """The installed CLI's help still lists every option of the reviewer command.

    Some CLIs ignore unknown options when `--help` is given, so the check compares the
    options with the help text. It needs no network and no credentials. It cannot find
    conflicts between arguments (for example, `codex review --commit` with instructions);
    only a real review run finds those. Skipped where the CLI is not installed, as in CI.
    """
    if shutil.which(reviewer) is None:
        pytest.skip(f"{reviewer} is not installed")
    command = reviewer_command("codex" if reviewer == "codex" else "claude")
    subcommand = [part for part in command if not part.startswith("-")][:2 if reviewer == "codex" else 1]
    result = subprocess.run([*subcommand, "--help"], capture_output=True, text=True, timeout=30, check=False)
    assert result.returncode == 0, result.stderr
    assert missing_options(command, result.stdout) == []


@pytest.mark.unit
@pytest.mark.parametrize("output,review,code", [
    ("- R1 must tools/review.py:12 policy literal\n- R9 should docs/a.md:3 style\n", Review(1, 1, True), 1),
    ("Summary\n* R4 should GateCore.lean:40 legacy marker\n", Review(0, 1, True), 0),
    ("No findings.\n", Review(0, 0, True), 0),
    ("Looks good to me.\n", Review(0, 0, False), 3),
])
def test_parse_review(output: str, review: Review, code: int) -> None:
    """Findings are counted by severity; output without the format is not trusted."""
    assert parse_review(output) == review
    assert exit_code(review) == code


def stub_tools(directory: Path, review_output: str) -> Path:
    """Write `jj`, `codex` and `claude` stubs; reviewers record their call in `call.json`."""
    directory.mkdir()
    (directory / "jj").write_text(f"#!/bin/sh\necho {COMMIT}\n")
    recorder = (f"#!{sys.executable}\nimport json, os, sys\n"
                f"json.dump({{'argv': sys.argv, 'stdin': sys.stdin.read(), 'environ': dict(os.environ)}},"
                f" open({str(directory / 'call.json')!r}, 'w'))\nprint({review_output!r})\n")
    for name in ("codex", "claude"):
        (directory / name).write_text(recorder)
    for name in ("jj", "codex", "claude"):
        (directory / name).chmod(0o755)
    return directory


def run_review(stubs: Path, extra: dict[str, str]) -> subprocess.CompletedProcess[str]:
    """Run the real script with the stubs first on PATH and only the given session markers."""
    environment = {name: value for name, value in os.environ.items()
                   if not name.startswith(("CLAUDE", "CODEX_", "AI_AGENT", "REVIEWER", GUARD))}
    environment.update(extra, PATH=f"{stubs}{os.pathsep}{os.environ['PATH']}")
    return subprocess.run([sys.executable, str(SCRIPT)], env=environment, capture_output=True, text=True,
                          timeout=15, check=False)


@pytest.mark.integration
def test_claude_caller_gets_isolated_codex_review(tmp_path: Path) -> None:
    """A Claude Code caller is reviewed by Codex, which sees no Claude markers and gets the checklist."""
    stubs = stub_tools(tmp_path / "bin", "- R2 must SqliteVerifier/Contract.lean:10 no plain words")
    result = run_review(stubs, {"CLAUDECODE": "1", "AI_AGENT": "claude-code"})
    call = json.loads((stubs / "call.json").read_text())
    assert result.returncode == 1, result.stderr
    assert Path(call["argv"][0]).name == "codex" and call["argv"][1:4] == ["exec", "--sandbox", "read-only"]
    assert "CLAUDECODE" not in call["environ"] and "AI_AGENT" not in call["environ"]
    assert call["environ"][GUARD] == "1" and "Output format" in call["stdin"] and COMMIT in call["stdin"]


@pytest.mark.integration
def test_codex_caller_gets_claude_review(tmp_path: Path) -> None:
    """A Codex caller is reviewed by Claude Code without Codex session markers."""
    stubs = stub_tools(tmp_path / "bin", "No findings.")
    result = run_review(stubs, {"CODEX_THREAD_ID": "t", "CODEX_SANDBOX": "seatbelt"})
    call = json.loads((stubs / "call.json").read_text())
    assert result.returncode == 0, result.stderr
    assert Path(call["argv"][0]).name == "claude"
    assert not any(name.startswith("CODEX_") for name in call["environ"])


@pytest.mark.integration
@pytest.mark.parametrize("markers,message", [
    ({GUARD: "1"}, "already inside a review"),
    ({"CLAUDECODE": "1", "CODEX_THREAD_ID": "t"}, "both"),
])
def test_review_refuses(tmp_path: Path, markers: dict[str, str], message: str) -> None:
    """A nested review, or a caller with both tools' markers, stops before any reviewer runs."""
    stubs = stub_tools(tmp_path / "bin", "No findings.")
    result = run_review(stubs, markers)
    assert result.returncode == 2 and message in result.stderr, result.stderr
    assert not (stubs / "call.json").exists()
