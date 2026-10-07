"""Checks and reference builds share the Linux-only pull-request schedule."""

from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
GUARD = "env.PLATFORM_RUNS == 'true'"
"""The condition that limits a step to the platforms that check this event."""
EXPLANATION_STEP = "Skip macOS checks on pull requests"
"""The explanatory step reports the skipped native platform without running it."""
pytestmark = [pytest.mark.unit]


def check_job_steps() -> list[tuple[str, str]]:
    """Name and condition of each step of the check job, so the tests can verify the platform guard."""
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
    """Linux runs checks and references; macOS runs them outside pull requests."""
    text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert ("PLATFORM_RUNS: ${{ matrix.system == 'x86_64-linux' || "
            "github.event_name != 'pull_request' }}") in text


def test_every_working_step_is_guarded() -> None:
    """Every working step is skipped on macOS pull requests, including reference setup."""
    steps = check_job_steps()
    assert steps, "No steps found in the check job"
    unguarded = [name for name, condition in steps
                 if GUARD not in condition and name != EXPLANATION_STEP]
    assert not unguarded, f"Steps that would run on macOS pull requests: {unguarded}"
    conditions = dict(steps)
    assert conditions[EXPLANATION_STEP] == "env.PLATFORM_RUNS != 'true'"
    reference = "Build checked API reference"
    assert conditions[reference] == GUARD + " && steps.scope.outputs.scope != 'docs'"
    assert conditions["Retain checked API reference"] == "always() && " + conditions[reference]


def test_cache_save_is_limited_to_main_and_nightly() -> None:
    """Pull requests, tags and manual runs can restore caches but cannot publish them."""
    text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    expected = ("save: ${{ github.event_name == 'schedule' || "
                "(github.event_name == 'push' && github.ref == 'refs/heads/main') }}")
    assert expected in text
    assert "save: true" not in text
