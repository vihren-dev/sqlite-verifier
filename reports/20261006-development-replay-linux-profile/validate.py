"""Check the retained Linux diagnostic against previous public evidence without replay."""

from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias, cast

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / "20261006-development-replay-headroom"


def mapping(value: Json) -> dict[str, Json]:
    """Reject a receipt that cannot provide its named evidence fields."""
    assert isinstance(value, dict), value
    return value


def decode(data: bytes) -> dict[str, Json]:
    """Read retained structured evidence for identity and timing comparisons."""
    return mapping(cast(Json, json.loads(data)))


def raw(name: str) -> bytes:
    """Recover the exact bytes observed in the failed setup or completed diagnostic."""
    return gzip.decompress((ROOT / (name + ".gz")).read_bytes())


def number(value: Json) -> int | float:
    """Require an actual measured number when recomputing stage totals."""
    assert type(value) in (int, float), value
    return cast(int | float, value)


def validate() -> None:
    """Check every archived hash, original result, timing and source/fixture denominator."""
    receipt = decode((ROOT / "receipt.json").read_bytes())
    manifest = decode((ROOT / "raw-sha256.json").read_bytes())
    assert set(manifest) == {str(path.relative_to(ROOT)) for path in ROOT.rglob("*.gz")}
    for name, entry in manifest.items():
        fields = mapping(entry)
        compressed = (ROOT / name).read_bytes()
        content = gzip.decompress(compressed)
        assert hashlib.sha256(compressed).hexdigest() == fields["sha256"], name
        assert hashlib.sha256(content).hexdigest() == fields["uncompressedSha256"], name
        assert len(content) == fields["uncompressedBytes"], name
    report = decode(raw("diagnostic/report.json"))
    old = decode(gzip.decompress((PREVIOUS / "linux/report.json.gz").read_bytes()))
    for field in ("runtime", "policy", "policySha256", "generic", "synthetic", "denominator", "selectedDenominator", "counts"):
        assert report[field] == old[field], field
    assert report["selectedDenominator"] == receipt["selectedIdentities"]
    assert report["denominator"] == receipt["fullDenominator"]
    summary = decode(raw("diagnostic/summary.json"))
    assert summary["measurement"] == report["measurement"]
    assert mapping(report["measurement"])["seconds"] == receipt["instrumentedPhaseSeconds"]
    assert mapping(report["measurement"])["limitSeconds"] == receipt["phaseLimitSeconds"]
    before, after = decode(raw("diagnostic/identity-before.json")), decode(raw("diagnostic/identity-after.json"))
    assert before == after == summary["hashesBefore"] == summary["hashesAfter"]
    previous_hashes = decode(gzip.decompress((PREVIOUS / "linux/identity-before.json.gz").read_bytes()))
    assert {key: value for key, value in before.items() if not key.endswith("/t04c_diagnostic.py")} == {
        key: value for key, value in previous_hashes.items() if not key.endswith("/../measure.py")}
    started, ended = summary["startedMonotonicNs"], summary["endedMonotonicNs"]
    assert isinstance(started, int) and isinstance(ended, int)
    assert (ended - started) / 1e9 == summary["outerInstrumentedSeconds"] == receipt["outerInstrumentedSeconds"]
    assert summary["stageObservations"] == decode(raw("diagnostic/stage-observations.json"))
    for name, value in mapping(summary["stageObservations"]).items():
        assert isinstance(value, list)
        calls = [mapping(call) for call in value]
        wall = sum(number(call["wallSeconds"]) for call in calls)
        user = sum(number(mapping(call["metricsDelta"])["parentUserSeconds"]) for call in calls)
        system = sum(number(mapping(call["metricsDelta"])["parentSystemSeconds"]) for call in calls)
        assert mapping(receipt["stageTotals"])[name] == {
            "calls": len(calls), "wallSeconds": wall, "parentUserSeconds": user,
            "parentSystemSeconds": system, "wallMinusParentCpuSeconds": wall - user - system}
    storage = mapping(summary["storage"])
    paths, storage_root = storage["fixturePaths"], storage["root"]
    assert isinstance(paths, list) and isinstance(storage_root, str)
    assert len(paths) == len(set(cast(list[str], paths))) == receipt["selectedIdentities"]
    assert all(isinstance(path, str) and Path(path).is_relative_to(storage_root)
               and Path(path).name == "case.db" for path in paths)
    assert storage["fixturesCleaned"] is True
    previous_source = gzip.decompress((PREVIOUS / "linux/source-before.log.gz").read_bytes())
    assert raw("diagnostic/source-before.log") == raw("diagnostic/source-after.log") == previous_source
    assert raw("preflight/source-before.log") == previous_source
    assert len(previous_source.splitlines()) == receipt["sourceFileCount"]
    assert raw("diagnostic/filesystem-before.txt") == raw("diagnostic/filesystem-after.txt")
    assert b"ext4" in raw("diagnostic/filesystem-before.txt")
    assert b"cProfile.Profile()" in raw("preflight/run.log")
    assert b"partially initialized module" in raw("preflight/run.log")
    assert not any(name.startswith("preflight/") and "report.json" in name for name in manifest)
    print("Diagnostic hashes, timings, full source checks and unchanged selection/verdicts pass.")


if __name__ == "__main__":
    validate()
