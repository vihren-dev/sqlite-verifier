"""Audit retained timing evidence and original bytes without running replay again."""

import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias

ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parents[1]
Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
"""Retained evidence uses only JSON values and has no runtime or compiler dependency."""
COMPARISON_FIELDS = ("corpusVersion", "casesSha256", "manifestSha256", "executionProfiles", "denominator",
    "selectedDenominator", "selectedNames", "selectedIdentities", "selectedIdentitiesSha256", "cases", "counts")
"""Historical identities, profiles and verdicts remain authoritative for each selected input."""


def read_original(name: str, root: Path = ROOT) -> dict[str, Json]:
    """Parse retained JSON; the caller must first verify its compressed and original bytes."""
    value = json.loads(gzip.decompress((root / name).read_bytes()))
    if not isinstance(value, dict):
        raise ValueError(f"{name}: expected a JSON object")
    return value


def validate(root: Path = ROOT) -> None:
    """Require exact source, helper, runtime, historical result and fixture bindings on both platforms."""
    bindings = json.loads((root / "raw-sha256.json").read_text())
    for name, binding in bindings.items():
        compressed = (root / name).read_bytes()
        assert hashlib.sha256(compressed).hexdigest() == binding["sha256"], name
        original = gzip.decompress(compressed)
        assert len(original) == binding["original_bytes"], name
        assert hashlib.sha256(original).hexdigest() == binding["original_sha256"], name
    source = read_original("source.json.gz", root)
    files = read_original("source-files.json.gz", root)
    helpers = read_original("helper-manifest.json.gz", root)
    summary = json.loads((root / "acceptance.json").read_text())
    assert summary["source_revision"] == source["source_revision"], "summary source"
    assert summary["phase_limit_seconds"] == 120 and summary["target_seconds_exclusive"] == 30, "summary limits"
    assert summary["complete_performance_acceptance"] is True and summary["task_done"] is False, "summary status"
    assert summary["model_agreement_claimed"] is False and summary["raw_artifacts"] == len(bindings), "summary scope"
    assert hashlib.sha256((root / "linux-evidence.tar.gz").read_bytes()).hexdigest() == summary["linux_evidence_archive_sha256"], "retrieval archive"
    for platform, prefix in (("darwin", "darwin/"), ("linux", "linux-originals/linux/")):
        receipt = read_original(prefix + "receipt.json.gz", root)
        report = read_original(prefix + "report.json.gz", root)
        before = read_original(prefix + "identity-before.json.gz", root)
        after = read_original(prefix + "identity-after.json.gz", root)
        assert before == after and receipt["bindingsUnchanged"], platform
        assert receipt["sourceCommit"] == source["source_revision"], platform
        assert before["archive"]["sha256"] == source["archive_sha256"], platform
        assert len(before["source"]["files"]) == len(files) == source["entries"], platform
        assert set(before["source"]["files"]) == set(files), platform
        for name, expected in files.items():
            actual = before["source"]["files"][name]
            if expected["type"] == "symlink":
                assert actual["link"] == expected["target"], name
                expected = files[str(Path(name).parent / expected["target"])]
            assert actual["sha256"] == expected["sha256"] and actual["bytes"] == expected["bytes"], name
        for name, expected in helpers.items():
            actual = before["helpers"]["files"][name]
            raw = gzip.decompress((root / "helpers" / (name + ".gz")).read_bytes())
            assert hashlib.sha256(raw).hexdigest() == actual["sha256"] == expected["sha256"], name
            assert len(raw) == actual["bytes"] == expected["bytes"], name
        historical = receipt["historicalReceipt"]
        relative = Path(historical["path"]).relative_to(before["source"]["root"])
        raw = (REPOSITORY / relative).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == historical["sha256"], platform
        previous = json.loads(raw)
        for side in ("generic", "synthetic"):
            assert report[side]["nativeReplayPassed"] is True, (platform, side)
            comparisons = {field: report[side][field] == previous[side][field] for field in COMPARISON_FIELDS}
            assert comparisons == receipt["comparisons"][side] and all(comparisons.values()), (platform, side)
        phase = receipt["phase"]
        paths = list(map(Path, phase["fixturePaths"]))
        storage = Path(receipt["conditionsBefore"]["storageRoot"])
        assert len(paths) == len(set(paths)) == report["selectedDenominator"] == 184, platform
        assert all(path.is_relative_to(storage) and path.name == "case.db" for path in paths), platform
        assert phase["fixturesCleaned"] and phase["failure"] is None, platform
        assert report["denominator"] == 4378 and report["counts"] == {"MODEL_UNSUPPORTED": 184}, platform
        assert report["policy"] == previous["policy"] and report["policySha256"] == previous["policySha256"], platform
        measurement = receipt["measurement"]
        assert measurement == report["measurement"], platform
        assert measurement["limitSeconds"] == receipt["phaseLimitSeconds"] == 120, platform
        assert receipt["targetSecondsExclusive"] == 30, platform
        assert receipt["underTarget"] == (measurement["seconds"] < 30) is True, platform
        outer = (phase["ended"]["monotonicNs"] - phase["started"]["monotonicNs"]) / 1e9
        assert outer == phase["outerPhaseSeconds"] and 0 < measurement["seconds"] <= outer < 120, platform
        assert receipt["valid"] and receipt["command"]["returncode"] == 0 and not receipt["command"]["timedOut"], platform
        assert receipt["conditionsBefore"]["storageDevice"] == receipt["conditionsAfter"]["storageDevice"], platform
        expected = {"phase_seconds": measurement["seconds"], "outer_seconds": outer,
            "start": phase["started"], "end": phase["ended"], "fixture_count": len(paths),
            "fixtures_cleaned": phase["fixturesCleaned"], "bindings_unchanged": receipt["bindingsUnchanged"],
            "storage_root": str(storage), "storage_device": receipt["conditionsBefore"]["storageDevice"]}
        assert summary["platforms"][platform] == expected, (platform, "summary")
    storage = read_original("darwin-storage-after-only.json.gz", root)
    original = read_original("darwin/receipt.json.gz", root)
    assert storage["matches_recorded_before_after"] and storage["observation"].startswith("after-only"), "darwin storage"
    assert storage["storage_device_now"] == original["conditionsBefore"]["storageDevice"], "darwin storage"
    assert "/System/Volumes/Data" in storage["system_df"] and "APFS" in storage["diskutil"], "darwin storage"
    print("Both original receipts, complete bindings, 184 native comparisons per platform and strict timing targets verify.")


if __name__ == "__main__":
    validate()
