"""Reference builds run on both native platforms; runtime checks retain their PR schedule."""

from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
GUARD = "env.PLATFORM_RUNS == 'true'"
"""The condition that limits a step to the platforms that check this event."""
EXPLANATION_STEP = "Skip macOS runtime checks on pull requests"
"""The explanatory step distinguishes skipped runtime checks from the native reference build."""
REFERENCE_STEPS = {
    "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803": "",
    "Select complete checks for the changed inputs": "",
    "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24": "steps.scope.outputs.scope != 'docs'",
    "Restore Nix builds and test results": "steps.scope.outputs.scope != 'docs'",
    "Build checked API reference": "steps.scope.outputs.scope != 'docs'",
    "Retain checked API reference": "always() && steps.scope.outputs.scope != 'docs'",
}
"""Only reference setup, generation and retention may run without the runtime platform guard."""
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
    """Linux always runs verifier checks; macOS runs them outside pull requests."""
    text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert ("PLATFORM_RUNS: ${{ matrix.system == 'x86_64-linux' || "
            "github.event_name != 'pull_request' }}") in text


def test_every_working_step_is_guarded() -> None:
    """macOS PRs build and retain the reference while every runtime step keeps its guard."""
    steps = check_job_steps()
    assert steps, "No steps found in the check job"
    unguarded = [name for name, condition in steps
                 if GUARD not in condition and name != EXPLANATION_STEP and name not in REFERENCE_STEPS]
    assert not unguarded, f"Steps that would run on macOS pull requests: {unguarded}"
    conditions = dict(steps)
    assert conditions[EXPLANATION_STEP] == "env.PLATFORM_RUNS != 'true'"
    assert {name: conditions[name] for name in REFERENCE_STEPS} == REFERENCE_STEPS
