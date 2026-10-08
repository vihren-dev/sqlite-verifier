"""Synthetic path intervals exercise the real campaign writer without performance trials."""

from collections.abc import Sequence
from pathlib import Path

import pytest

from migration_check.structural import Json
import tools.bundle_measurement_campaign as campaign
from tools.bundle_measurement_paths import Flow, PathObservation, TrialSpec


def synthetic_paths(monkeypatch: pytest.MonkeyPatch, differences: Sequence[int], *,
                    invalid_pair: int | None = None,
                    interruption: tuple[int, Flow] | None = None,
                    interruption_error: BaseException | None = None) -> list[tuple[int, Flow]]:
    """Keep real evidence files while supplying deterministic intervals instead of running a child."""
    calls: list[tuple[int, Flow]] = []

    def record_path(spec: TrialSpec, flow: Flow, directory: Path, baseline: dict[str, Json]) -> PathObservation:
        """Retain explicitly synthetic raw files, including a partially observed interrupted path."""
        number = int(directory.parent.name.removeprefix("pair-"))
        calls.append((number, flow))
        directory.mkdir()
        (directory / "stdout.bin").write_bytes(f"synthetic fixture {number} {flow}".encode())
        (directory / "stderr.bin").write_bytes(b"")
        if interruption == (number, flow):
            raise interruption_error if interruption_error is not None else KeyboardInterrupt("synthetic fixture interruption")
        before = campaign.retain_identity(directory / "identity-before.json.gz", baseline)
        after = campaign.retain_identity(directory / "identity-after.json.gz", baseline)
        artifacts = campaign.retain_identity(directory / "artifacts.json.gz", {"synthetic_fixture": True})
        start = number * 10_000_000 + (0 if flow == "verify" else 2_000_000)
        wall = 1_000_000 + (differences[number - 1] if flow == "bundle" else 0)
        invalid = ("synthetic invalid condition",) if number == invalid_pair and flow == "verify" else ()
        return PathObservation(flow, start, start + wall, (), invalid, before, after, artifacts, (),
                               directory.stat().st_dev, {"synthetic_fixture": True}, {"synthetic_fixture": True})

    monkeypatch.setattr(campaign, "execute_path", record_path)
    return calls
