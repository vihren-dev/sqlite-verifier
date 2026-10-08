"""Check complete T04c receipts and their target outcome without replay or builds."""

from __future__ import annotations

from datetime import datetime, timedelta
import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias, cast

from receipt_policy import (FULL_DENOMINATOR, LEAN_VERSION_PREFIX, MODEL_CLASSIFICATION,
                            PHASE_LIMIT, SELECTED_IDENTITIES, SOURCE_COMMIT, SOURCE_FILES, TARGET)

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
FIELDS = (
    "corpusVersion", "casesSha256", "manifestSha256", "executionProfiles", "denominator",
    "selectedDenominator", "selectedNames", "selectedIdentities", "selectedIdentitiesSha256", "cases", "counts",
)


def mapping(value: Json) -> dict[str, Json]:
    """Narrow JSON to an object so field checks can proceed; fail for other shapes."""
    assert isinstance(value, dict), value
    return value


def decode(content: bytes) -> dict[str, Json]:
    """Read a retained JSON object without executing the capture helper."""
    return mapping(cast(Json, json.loads(content)))


def raw(name: str) -> bytes:
    """Recover exact original bytes from the immutable compressed artifact."""
    return gzip.decompress((ROOT / (name + ".gz")).read_bytes())


def document(name: str) -> dict[str, Json]:
    """Read a structured original artifact after compressed-byte verification."""
    return decode(raw(name))


def sha(content: bytes) -> str:
    """Bind independently serialized identities and exact retained bytes."""
    return hashlib.sha256(content).hexdigest()


def number(value: Json) -> int | float:
    """Reject booleans and strings in an actual timing or device observation."""
    assert type(value) in (int, float), value
    return cast(int | float, value)


def stamp(value: Json) -> tuple[int | float, datetime]:
    """Require actual monotonic and explicitly UTC observations at each boundary."""
    fields = mapping(value)
    utc = fields["utc"]
    assert isinstance(utc, str)
    instant = datetime.fromisoformat(utc)
    assert instant.utcoffset() == timedelta(0)
    return number(fields["monotonicNs"]), instant


def check_platform(platform: str, summary: dict[str, Json], source: dict[str, Json]) -> None:
    """Recompute report bindings, timing, file identities, actual paths and cleanup."""
    report, receipt = document(f"{platform}/report.json"), document(f"{platform}/receipt.json")
    original_path = REPO / f"reports/20261002-adr5-review-v5-sample-{platform}.json"
    original_bytes = original_path.read_bytes()
    original = decode(original_bytes)
    observed = mapping(mapping(summary["platforms"])[platform])
    assert sha(original_bytes) == observed["historicalReceiptSha256"] == mapping(receipt["historicalReceipt"])["sha256"]
    for side in ("generic", "synthetic"):
        binding = mapping(report[side])
        assert all(binding[field] == mapping(original[side])[field] for field in FIELDS), (platform, side)
        assert binding["nativeReplayPassed"] is True
        encoded = json.dumps(binding["selectedIdentities"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        assert sha(encoded) == binding["selectedIdentitiesSha256"]
    assert report["policy"] == original["policy"] and report["policySha256"] == original["policySha256"]
    assert report["denominator"] == original["denominator"] == summary["fullDenominator"] == FULL_DENOMINATOR
    assert report["selectedDenominator"] == SELECTED_IDENTITIES
    assert report["counts"] == original["counts"] == {MODEL_CLASSIFICATION: SELECTED_IDENTITIES}
    measurement = mapping(report["measurement"])
    seconds = number(measurement["seconds"])
    assert measurement == receipt["measurement"] and seconds == observed["phaseSeconds"]
    assert measurement["phase"] == "fresh-load-native-replay-model-classification"
    assert measurement["limitSeconds"] == receipt["phaseLimitSeconds"] == PHASE_LIMIT and 0 < seconds < PHASE_LIMIT
    assert receipt["underTarget"] == observed["underTarget"] == (seconds < TARGET)
    assert receipt["valid"] is True and receipt["bindingsUnchanged"] is True and observed["evidenceValid"] is True
    command = document(f"{platform}/commands/command-0000.json")
    observation = mapping(receipt["command"])
    assert command["returncode"] == observation["returncode"] == 0
    assert command["timed_out"] is False and observation["timedOut"] is False
    assert all(command[key] == observation[key] for key in ("stdout", "stderr"))
    assert command["elapsed"] == observation["elapsedSeconds"]
    stdout = command["stdout"]
    assert isinstance(stdout, str) and decode(stdout.encode())["measurement"] == measurement
    phase = document(f"{platform}/phase-result.json")
    assert phase == receipt["phase"] and phase["failure"] is None and phase["fixturesCleaned"] is True
    assert phase["started"] == document(f"{platform}/phase-start.json") == observed["started"]
    assert phase["ended"] == observed["ended"]
    started, ended = stamp(phase["started"]), stamp(phase["ended"])
    capture_start, capture_end = stamp(document(f"{platform}/capture-start.json")), stamp(receipt["captureEnded"])
    assert capture_start[0] < started[0] < ended[0] < capture_end[0]
    assert capture_start[1] < started[1] < ended[1] < capture_end[1]
    outer = (ended[0] - started[0]) / 1e9
    assert outer == phase["outerPhaseSeconds"] == observed["outerPhaseSeconds"] and seconds <= outer < PHASE_LIMIT
    assert abs((ended[1] - started[1]).total_seconds() - outer) < 0.1
    before = document(f"{platform}/identity-before.json")
    assert before == document(f"{platform}/identity-after.json")
    assert before["leanVersion"].startswith(LEAN_VERSION_PREFIX)
    assert mapping(before["archive"])["sha256"] == source["archiveSha256"] == summary["archiveSha256"]
    assert mapping(before["archive"])["bytes"] == source["archiveBytes"] == summary["archiveBytes"]
    files = mapping(mapping(before["source"])["files"])
    regular, links = mapping(source["regularFiles"]), mapping(source["symlinks"])
    assert len(regular) == SOURCE_FILES and set(files) == set(regular) | set(links)
    assert links == summary["sourceSymlinks"] == {"CLAUDE.md": "AGENTS.md"}
    assert all(mapping(files[name])["sha256"] == digest for name, digest in regular.items())
    assert mapping(files["CLAUDE.md"])["link"] == "AGENTS.md"
    assert mapping(files["CLAUDE.md"])["sha256"] == regular["AGENTS.md"]
    runtime = mapping(before["runtime"])
    assert runtime["root"] == observed["runtime"] and len(mapping(runtime["files"])) == observed["runtimeFiles"]
    for binding in mapping(report["runtime"]).values():
        fields = mapping(binding)
        assert fields["sha256"] == mapping(mapping(runtime["files"])[str(fields["path"])])["sha256"]
    assert before["python"] == observed["python"] and before["nativeLibraries"] == observed["nativeLibraries"]
    profiles = [mapping(profile) for side in ("generic", "synthetic") for profile in cast(list[Json], mapping(report[side])["executionProfiles"])]
    assert set(mapping(before["nativeLibraries"])) == {str(profile["engineVersion"]) for profile in profiles}
    helpers = mapping(mapping(before["helpers"])["files"])
    assert set(helpers) == {"t04c_capture.py", "t04c_metadata.py"}
    assert all(mapping(fields)["sha256"] == sha(raw(f"helpers/{name}")) for name, fields in helpers.items())
    for side in ("before", "after"):
        conditions = document(f"{platform}/conditions-{side}.json")
        assert conditions == receipt["conditions" + side.title()]
        assert conditions["storageRoot"] == observed["storageRoot"] and conditions["storageDevice"] == observed["storageDevice"]
        assert conditions["loadAverage"] == observed["load" + side.title()]
        assert conditions["osFileCaches"] == "not flushed; residency is not observed"
    storage_root = observed["storageRoot"]
    assert isinstance(storage_root, str)
    paths = phase["fixturePaths"]
    assert isinstance(paths, list) and len(paths) == len(set(cast(list[str], paths))) == SELECTED_IDENTITIES
    assert all(isinstance(path, str) and Path(path).is_relative_to(storage_root) and Path(path).name == "case.db" for path in paths)
    if platform == "linux":
        assert '"fstype": "ext4"' in str(mapping(document("linux/conditions-before.json")["filesystem"])["findmnt"])
    else:
        reconciliation = document("darwin/filesystem-reconciliation.json")
        assert reconciliation["observedMonotonicNs"] > ended[0]
        assert reconciliation["storageDeviceNow"] == reconciliation["dataMountDeviceNow"] == observed["storageDevice"]
        assert "/System/Volumes/Data" in str(mapping(reconciliation["nativeDf"])["stdout"])
        assert "File System Personality:   APFS" in str(mapping(reconciliation["diskutil"])["stdout"])


def validate() -> None:
    """Validate immutable receipts while keeping a valid target miss as a miss."""
    summary = decode((ROOT / "receipt.json").read_bytes())
    manifest = decode((ROOT / "raw-sha256.json").read_bytes())
    assert set(manifest) == {str(path.relative_to(ROOT)) for path in ROOT.rglob("*.gz")}
    assert len(manifest) == summary["rawArtifacts"]
    for name, entry in manifest.items():
        fields = mapping(entry)
        compressed = (ROOT / name).read_bytes()
        content = gzip.decompress(compressed)
        assert sha(compressed) == fields["sha256"] and sha(content) == fields["uncompressedSha256"], name
        assert len(content) == fields["uncompressedBytes"], name
    source = document("source-manifest.json")
    assert source["sourceCommit"] == summary["sourceCommit"] == SOURCE_COMMIT
    assert summary["phaseLimitSeconds"] == PHASE_LIMIT and summary["targetSecondsExclusive"] == TARGET
    transfer, verified = document("transfer-manifest.json"), document("linux/transfer-receipt.json")
    assert verified["phaseStarted"] is False and verified["symlinkChecked"] is True
    assert set(mapping(verified["sourceChecks"])) == set(mapping(source["regularFiles"]))
    assert all(value is True for value in mapping(verified["sourceChecks"]).values())
    assert set(mapping(verified["transferChecks"])) == set(transfer)
    assert all(value is True for value in mapping(verified["transferChecks"]).values())
    assert mapping(transfer["source-5d15607f-public.tar"])["sha256"] == source["archiveSha256"]
    for name in ("source-manifest.json", "t04c_capture.py", "t04c_metadata.py"):
        content = raw(name if name.endswith(".json") else "helpers/" + name)
        assert sha(content) == mapping(transfer[name])["sha256"] and len(content) == mapping(transfer[name])["bytes"]
    assert document("preflight/archive-preflight-failure.json")["phaseStarted"] is False
    assert document("preflight/helper-preflight-failure.json")["phaseInvoked"] is False
    assert document("preflight/linux-bootstrap-preflight-failure.json")["phaseStarted"] is False
    assert raw("preflight/source-5d15607f.tar") == b""
    for platform in ("darwin", "linux"):
        check_platform(platform, summary, source)
    platforms = [mapping(value) for value in mapping(summary["platforms"]).values()]
    assert summary["evidenceValid"] is True
    assert summary["targetMet"] == all(value["underTarget"] is True for value in platforms) is False
    assert summary["taskStatus"] == "IN PROGRESS"
    retrieval = document("linux/retrieval-manifest.json")
    assert retrieval["nativeStorageEntries"] == []
    for name, fields in mapping(retrieval["files"]).items():
        content = raw(name if name.startswith("linux/") else "linux/" + name)
        assert sha(content) == mapping(fields)["sha256"] and len(content) == mapping(fields)["bytes"]
    print("Complete 184-case receipts pass; Darwin meets 30 seconds, Linux misses; task remains IN PROGRESS.")


if __name__ == "__main__":
    validate()
