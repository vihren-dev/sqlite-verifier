"""The shared frozen-input boundary rejects tampering and native drift before tier classification."""

from pathlib import Path
import json
import shutil
import sys

import pytest

from conformance import replay_tiers
from conformance.case_format import Json
from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
GENERIC = ROOT / "conformance/corpus-v4"
SYNTHETIC = ROOT / "conformance/synthetic-workload"
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "parser-library")]


@pytest.mark.parametrize("binding", ["digest", "profile", "evidence"])
def test_changed_frozen_bindings_fail_before_replay(
        tmp_path: Path, runtime_root: Path, binding: str) -> None:
    """The tier uses the ordinary digest, profile and retained-proof validation boundary."""
    generic = tmp_path / "generic"
    shutil.copytree(GENERIC, generic)
    manifest_path = generic / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if binding == "digest":
        manifest["casesSha256"] = "0" * 64
    elif binding == "profile":
        manifest["executionProfiles"][0]["foreignKeys"] = not manifest["executionProfiles"][0]["foreignKeys"]
    else:
        manifest["extraction"]["sha256"] = "0" * 64
    manifest_path.write_text(json.dumps(manifest))
    with pytest.raises(ValueError):
        replay_tiers.report(generic, SYNTHETIC, runtime_root)


def test_changed_synthetic_source_fails_bound_input_loading(tmp_path: Path, runtime_root: Path) -> None:
    """Synthetic SQL inventory binding is required in addition to its frozen payload digest."""
    source = tmp_path / "synthetic"
    shutil.copytree(SYNTHETIC, source)
    with (source / "empty.sql").open("a") as stream:
        stream.write("\n")
    with pytest.raises(ValueError, match="source inventory differs"):
        replay_tiers.report(GENERIC, source, runtime_root)


def test_native_mismatch_fails_the_tier(monkeypatch: pytest.MonkeyPatch, runtime_root: Path) -> None:
    """Fresh SQLite observation drift must propagate before model classification can pass."""
    def changed_native(records: list[dict[str, Json]], *, temporary_root: Path | None = None,
                       fixture_paths: list[Path] | None = None) -> None:
        """Stand in for the observable retained-versus-fresh native failure."""
        raise ValueError("Native replay changed: selected-case")
    monkeypatch.setattr(replay_tiers, "replay_native_cases", changed_native)
    with pytest.raises(ValueError, match="Native replay changed"):
        replay_tiers.report(GENERIC, SYNTHETIC, runtime_root)


def test_legacy_v4_tier_still_replays_its_original_sample(tmp_path: Path, runtime_root: Path) -> None:
    """Explicit historical input preserves its 100 selected cases without replaying all 1,264 natively."""
    output = tmp_path / "legacy-tier.json"
    child = run_command([sys.executable, "-m", "conformance.replay_tiers", "--corpus", str(GENERIC),
        "--synthetic", str(SYNTHETIC), "--runtime-root", str(runtime_root), "--output", str(output)],
        cwd=ROOT, timeout=replay_tiers.PHASE_LIMIT_SECONDS)
    assert child.returncode == 0, child.stdout + child.stderr
    result = json.loads(output.read_text())
    assert result["generic"]["corpusVersion"] == 4
    assert result["generic"]["denominator"] == 1264
    assert result["selectedDenominator"] == 100
    assert result["generic"]["nativeReplayPassed"] and result["synthetic"]["nativeReplayPassed"]
    assert sum(result["counts"].values()) == 100
    assert not {"DISAGREE", "HARNESS_ERROR"} & result["counts"].keys()
    assert result["measurement"]["seconds"] < result["measurement"]["limitSeconds"] == replay_tiers.PHASE_LIMIT_SECONDS
