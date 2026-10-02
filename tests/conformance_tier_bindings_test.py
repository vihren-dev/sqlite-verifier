"""The shared frozen-input boundary rejects tampering and native drift before tier classification."""

from pathlib import Path
import json
import shutil

import pytest

from conformance import replay_tiers
from conformance.case_format import Json

ROOT = Path(__file__).resolve().parents[1]
GENERIC = ROOT / "conformance/corpus-v4"
SYNTHETIC = ROOT / "conformance/synthetic-workload"
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite-parser")]


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
    def changed_native(records: list[dict[str, Json]]) -> None:
        """Stand in for the observable retained-versus-fresh native failure."""
        raise ValueError("Native replay changed: selected-case")
    monkeypatch.setattr(replay_tiers, "native_replay", changed_native)
    with pytest.raises(ValueError, match="Native replay changed"):
        replay_tiers.report(GENERIC, SYNTHETIC, runtime_root)
