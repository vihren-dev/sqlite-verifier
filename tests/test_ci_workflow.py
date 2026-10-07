"""On pull requests, the macOS job only reports; every working step is skipped there.

The repository ruleset requires a result from the macOS job, so the job runs on pull
requests but must not build or upload anything. A step without the platform guard
would run on macOS pull requests, and an upload step would then fail for lack of files.
"""

from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
GUARD = "env.PLATFORM_RUNS == 'true'"
"""The condition that limits a step to the platforms that check this event."""
pytestmark = [pytest.mark.unit]


def check_job_steps() -> list[tuple[str, str]]:
    """Name and condition of each step of the check job, read from the workflow text."""
    text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    job = text[text.index("\n  check:\n"):text.index("\n  release:\n")]
    steps: list[tuple[str, str]] = []
    for block in re.split(r"\n      - ", "\n" + job.split("\n    steps:\n", 1)[1])[1:]:
        name = re.search(r"(?:^|\n\s*)name: (.+)", block)
        uses = re.match(r"uses: (\S+)", block)
        condition = re.search(r"\n        if: (.+)", block) or re.match(r"if: (.+)", block)
        label = name.group(1) if name else (uses.group(1) if uses else block.splitlines()[0])
        steps.append((label.strip(), condition.group(1).strip() if condition else ""))
    return steps


def test_platform_runs_skips_macos_only_on_pull_requests() -> None:
    """Linux always checks; macOS checks every event except pull requests."""
    text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert ("PLATFORM_RUNS: ${{ matrix.system == 'x86_64-linux' || "
            "github.event_name != 'pull_request' }}") in text


def test_every_working_step_is_guarded() -> None:
    """Only the explanatory step runs on macOS pull requests; all others carry the guard."""
    steps = check_job_steps()
    assert steps, "No steps found in the check job"
    unguarded = [name for name, condition in steps
                 if GUARD not in condition and name != "Skip macOS checks on pull requests"]
    assert not unguarded, f"Steps that would run on macOS pull requests: {unguarded}"
    assert dict(steps)["Skip macOS checks on pull requests"] == "env.PLATFORM_RUNS != 'true'"
