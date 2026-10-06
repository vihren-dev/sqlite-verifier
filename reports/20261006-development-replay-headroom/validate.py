"""Check retained T04c evidence without replaying inputs or rebuilding a runtime."""

from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias, cast

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
FIELDS = (
    "corpusVersion", "casesSha256", "manifestSha256", "executionProfiles",
    "denominator", "selectedDenominator", "selectedNames", "selectedIdentities",
    "selectedIdentitiesSha256", "cases", "counts",
)


def mapping(value: Json) -> dict[str, Json]:
    """Reject a receipt shape that cannot provide named evidence fields."""
    assert isinstance(value, dict), value
    return value


def decode(data: bytes) -> dict[str, Json]:
    """Read a retained JSON object for checks of its actual observations."""
    return mapping(cast(Json, json.loads(data)))


def raw(name: str) -> bytes:
    """Return the exact uncompressed bytes of an archived observation."""
    return gzip.decompress((ROOT / (name + ".gz")).read_bytes())


def check_raw_hashes() -> None:
    """Detect changes to compressed evidence or the original observed bytes."""
    manifest = decode((ROOT / "raw-sha256.json").read_bytes())
    assert set(manifest) == {
        str(path.relative_to(ROOT)) for path in ROOT.rglob("*.gz")
    }
    for name, entry in manifest.items():
        fields = mapping(entry)
        compressed = (ROOT / name).read_bytes()
        content = gzip.decompress(compressed)
        assert hashlib.sha256(compressed).hexdigest() == fields["sha256"], name
        assert hashlib.sha256(content).hexdigest() == fields["uncompressedSha256"], name
        assert len(content) == fields["uncompressedBytes"], name


def check_reports(receipt: dict[str, Json]) -> None:
    """Compare both original report observations with their historical identities."""
    for platform in ("darwin", "linux"):
        report = decode(raw(f"{platform}/report.json"))
        old_path = REPO / f"reports/20261002-adr5-review-v5-sample-{platform}.json"
        old_bytes = old_path.read_bytes()
        assert hashlib.sha256(old_bytes).hexdigest() == mapping(
            receipt["historicalReceiptSha256"]
        )[platform]
        old = decode(old_bytes)
        for side in ("generic", "synthetic"):
            for field in FIELDS:
                assert mapping(report[side])[field] == mapping(old[side])[field], (platform, side, field)
        assert report["policy"] == old["policy"]
        assert report["policySha256"] == old["policySha256"]
        assert report["selectedDenominator"] == 184
        assert report["counts"] == old["counts"] == {"MODEL_UNSUPPORTED": 184}
        measurement = mapping(report["measurement"])
        assert measurement["phase"] == "fresh-load-native-replay-model-classification"
        assert measurement["limitSeconds"] == 120
        seconds = measurement["seconds"]
        assert isinstance(seconds, float) and 0 < seconds < 120
        assert seconds == mapping(receipt[platform])["phaseSeconds"]


def check_linux(receipt: dict[str, Json]) -> None:
    """Check complete Linux path, timestamp, source and runtime identity retention."""
    summary = decode(raw("linux/summary.json"))
    before = decode(raw("linux/identity-before.json"))
    after = decode(raw("linux/identity-after.json"))
    assert before == after == summary["hashesBefore"] == summary["hashesAfter"]
    started, ended = summary["startedMonotonicNs"], summary["endedMonotonicNs"]
    assert isinstance(started, int) and isinstance(ended, int) and ended > started
    assert (ended - started) / 1e9 == summary["outerPhaseSeconds"]
    assert summary["outerPhaseSeconds"] == mapping(receipt["linux"])["outerPhaseSeconds"]
    assert summary["underTarget"] is False
    storage = mapping(summary["storage"])
    storage_root = storage["root"]
    assert isinstance(storage_root, str)
    paths = storage["fixturePaths"]
    assert isinstance(paths, list) and len(paths) == 184
    assert len(set(cast(list[str], paths))) == 184
    for path in paths:
        assert isinstance(path, str)
        assert Path(path).is_relative_to(storage_root) and Path(path).name == "case.db"
    assert storage["fixturesCleaned"] is True
    lines = raw("linux/source.sha256").decode().splitlines()
    assert len(lines) == mapping(receipt["linux"])["sourceFileCount"] == 835
    source_hashes = dict(line.split("  ", 1)[::-1] for line in lines)
    source_root = str(mapping(receipt["linux"])["remoteRoot"]) + "/source/"
    for path, digest in before.items():
        if path.startswith(source_root):
            relative = path.removeprefix(source_root)
            if relative.startswith(("conformance/", "migration_check/")):
                assert source_hashes["./" + relative] == digest, path
    names = [line.split("  ", 1)[1] for line in lines]
    for log in ("source-before.log", "source-after.log"):
        checks = raw("linux/" + log).decode().splitlines()
        assert len(checks) == len(names)
        for name, check in zip(names, checks, strict=True):
            assert check in (name + ": OK", "'" + name + "': OK"), (name, check)
    helper_digest = hashlib.sha256(raw("linux/measure.py")).hexdigest()
    assert helper_digest == before[next(key for key in before if key.endswith("/../measure.py"))]
    transfer = dict(line.split("  ", 1)[::-1] for line in raw("linux/transfer.sha256").decode().splitlines())
    assert transfer == {
        "headroom-source-82f2d178.tar": mapping(receipt["linux"])["sourceArchiveSha256"],
        "headroom-linux-measure.py": helper_digest,
        "headroom-linux-driver.sh": hashlib.sha256(raw("linux/driver.sh")).hexdigest(),
    }
    observed = mapping(mapping(receipt["linux"])["runtimeHashesObservedAfter"])
    runtime = summary["runtime"]
    assert isinstance(runtime, str)
    assert runtime == mapping(receipt["linux"])["runtime"]
    assert before[runtime + "/build/sqlite-parser"] == observed["parser"]
    assert before[runtime + "/.lake/build/bin/conformance-runner"] == observed["compiledModel"]


def check_darwin(receipt: dict[str, Json]) -> None:
    """Keep the completed Darwin phase separate from its missing ancillary fields."""
    summary = decode(raw("darwin/summary-recovered.json"))
    original = decode(raw("darwin/report.json"))
    assert summary["measurement"] == original["measurement"]
    assert summary["underTarget"] is True
    assert mapping(summary["storage"])["fixturePaths"] is None
    assert mapping(summary["storage"])["fixtureCountAssertedInDriver"] == 184
    assert "hashesBefore" not in summary and "hashesAfter" not in summary
    assert "startedMonotonicNs" not in summary and "endedMonotonicNs" not in summary
    darwin = mapping(receipt["darwin"])
    assert darwin["outerStartedMonotonicNs"] is None
    assert darwin["outerEndedMonotonicNs"] is None
    assert darwin["actualFixturePaths"] is None
    assert darwin["processExit"] == 1
    assert b"PosixPath is not JSON serializable" in raw("darwin/run.log")
    after_only = mapping(summary["hashesRetainedAfterOnly"])
    helper = next(key for key in after_only if key.endswith("/measure.py"))
    assert hashlib.sha256(raw("darwin/measure.py")).hexdigest() == after_only[helper]


if __name__ == "__main__":
    evidence = decode((ROOT / "receipt.json").read_bytes())
    check_raw_hashes()
    check_reports(evidence)
    check_linux(evidence)
    check_darwin(evidence)
    print("Retained hashes, 184 identities/verdicts, Linux paths/timestamps/source and Darwin limits pass.")
