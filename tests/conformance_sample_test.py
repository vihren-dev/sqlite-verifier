"""The actual frozen replay tier proves mandatory coverage and fresh timing through its CLI."""

from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

import pytest

from conformance import replay_tiers
from conformance.corpus import load
from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
GENERIC = ROOT / "conformance/corpus-v5"
SYNTHETIC = ROOT / "conformance/synthetic-workload"
pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite-parser")]


def test_frozen_cli_replays_every_authored_and_synthetic_case_within_bound(
        tmp_path: Path, runtime_root: Path) -> None:
    """The same command as the development target checks fresh native truth and current model."""
    output = tmp_path / "sample.json"
    child = run_command([sys.executable, "-m", "conformance.replay_tiers",
        "--runtime-root", str(runtime_root), "--output", str(output)],
        cwd=ROOT, timeout=replay_tiers.PHASE_LIMIT_SECONDS)
    assert child.returncode == 0, child.stdout + child.stderr
    result = json.loads(output.read_text())
    manifest, records = load(GENERIC)
    selected = result["generic"]["selectedNames"]
    authored = {record["name"] for record in records if record["part"] in replay_tiers.AUTHORED_PARTS}
    sources = {shard["source"] for shard in manifest["shards"] if shard["part"] == "upstream"}
    assert manifest["corpusVersion"] == 5 and len(authored) == 69 and authored <= set(selected)
    additional = min(8, len(records) - len(authored) - len(sources))
    assert len(selected) == len(authored) + len(sources) + additional
    assert {identity["upstreamSource"] for identity in result["generic"]["selectedIdentities"]
            if identity["part"] == "upstream"} == sources
    synthetic_inventory = json.loads((SYNTHETIC / "workload.json").read_text())
    assert set(result["synthetic"]["selectedNames"]) == {case["name"] for case in synthetic_inventory["cases"]}
    assert result["selectedDenominator"] == len(selected) + 2
    assert result["denominator"] == len(records) + 2
    assert result["generic"]["denominator"] == manifest["recordedCases"] and result["synthetic"]["denominator"] == 2
    assert result["generic"]["casesSha256"] == manifest["casesSha256"]
    assert result["policy"] == replay_tiers.POLICY
    assert result["policySha256"] == replay_tiers.digest(result["policy"])
    for binding in result["runtime"].values():
        assert binding["sha256"] == hashlib.sha256((runtime_root / binding["path"]).read_bytes()).hexdigest()
    for label, directory in (("generic", GENERIC), ("synthetic", SYNTHETIC / "corpus")):
        section = result[label]
        assert section["manifestSha256"] == hashlib.sha256((directory / "manifest.json").read_bytes()).hexdigest()
        assert section["selectedIdentitiesSha256"] == replay_tiers.digest(section["selectedIdentities"])
        assert section["nativeReplayPassed"]
        assert section["counts"] == dict(Counter(case["verdict"] for case in section["cases"]))
        assert [case["name"] for case in section["cases"]] == section["selectedNames"]
    assert sum(result["counts"].values()) == result["selectedDenominator"]
    assert not {"DISAGREE", "HARNESS_ERROR"} & result["counts"].keys()
    assert result["measurement"]["phase"] == "fresh-load-native-replay-model-classification"
    assert result["measurement"]["seconds"] < result["measurement"]["limitSeconds"] == replay_tiers.PHASE_LIMIT_SECONDS
