"""Keep the sole complete Linux target miss intact without loading, replaying or compiling."""

from datetime import datetime, timedelta
import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias, cast

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
SOURCE_COMMIT = "c3e8f5186e2865b5cdc0ea5af1a9d0924531752a"
"""The approved executor integration supplies every compiled and Python input."""
PRIOR_DRIVER_SOURCE = "5d15607fdf78d0a209b539ca158939739b54d377"
"""Only this former evidence label changes in the reviewed driver."""
RUNTIME = "/nix/store/ixl6nwa1nk8ah8138axkqkgian4a27bc-sqlite-verifier-conformance"
"""The exact native Linux runtime was built and identified before this phase."""
COUNTS = {"source": 1113, "runtime": 17936, "denominator": 4378, "selected": 184, "raw": 20}
"""Require complete source/output, binding denominator, selection and original artifact inventories."""
PHASE_LIMIT, TARGET, UTC_TOLERANCE = 120, 30, 0.1
"""Keep the owner-approved guard, exclusive target and clock-agreement tolerance separate."""
MODEL_CLASSIFICATION = "MODEL_UNSUPPORTED"
"""Unsupported-only model results establish no supported agreement despite passing native comparisons."""
MEASUREMENT_PHASE = "fresh-load-native-replay-model-classification"
"""The unchanged report times loading, native replay and classification together."""
ORIGINAL_FILE_COUNT = 13
"""Every original remote phase/preflight/report artifact remains retrieved and hashed."""
FIELDS = ("corpusVersion", "casesSha256", "manifestSha256", "executionProfiles", "denominator",
          "selectedDenominator", "selectedNames", "selectedIdentities", "selectedIdentitiesSha256", "cases", "counts")
"""Every frozen selection/profile/evidence field must match the earlier v5 receipt."""
BUILD_RECORD = "reports/20261007-development-replay-executor-runtime/linux/linux/identity-after.json.gz"
"""The reviewed exact-source build independently identifies these reused runtime/input bytes."""
HISTORICAL_RECORD = "reports/20261002-adr5-review-v5-sample-linux.json"
"""The selection and classifications are fixed before this performance observation."""


FILESYSTEM_TYPE = "ext4"
"""This receipt measures ordinary ext4 fixture storage on the Linux host."""
CACHE_QUALIFICATION = "not flushed; residency is not observed"
"""The retained observation makes no cold-cache or cache-residency claim."""


def expect(condition: bool, context: str) -> None:
    """Name a failed evidence field and direct the reader to retained originals."""
    if not condition:
        raise ValueError(f"{context}. Compare the retained original report and identity manifests.")


def obj(value: Json, context: str) -> dict[str, Json]:
    """Narrow one JSON object so malformed shapes cannot become passing fields."""
    expect(isinstance(value, dict), f"{context}: expected a retained JSON object")
    return cast(dict[str, Json], value)


def raw(root: Path, name: str) -> bytes:
    """Decompress one retained artifact. The caller must first check its inventory and hashes."""
    return gzip.decompress((root / (name + ".gz")).read_bytes())


def read(root: Path, name: str) -> dict[str, Json]:
    """Decode one retained object without executing its helper."""
    return obj(cast(Json, json.loads(raw(root, name))), name)


def stamp(value: Json, context: str) -> tuple[int, datetime]:
    """Require actual nanosecond and explicitly UTC observations at each boundary."""
    fields = obj(value, context)
    expect(type(fields["monotonicNs"]) is int and isinstance(fields["utc"], str), "Clock stamp types differ")
    instant = datetime.fromisoformat(cast(str, fields["utc"]))
    expect(instant.utcoffset() == timedelta(0), "Clock stamp must use UTC")
    return cast(int, fields["monotonicNs"]), instant


def validate(root: Path) -> None:
    """Check full identities, ordered paths and original verdicts while preserving underTarget=false."""
    repo = Path(__file__).resolve().parents[2]
    hashes = json.loads((root / "raw-sha256.json").read_text())
    expect(len(hashes) == COUNTS["raw"] and set(hashes) == {str(p.relative_to(root)) for p in root.rglob("*.gz")}, "Raw artifact inventory differs")
    for name, expected in hashes.items():
        compressed = (root / name).read_bytes(); content = gzip.decompress(compressed)
        expect({"rawSha256": hashlib.sha256(content).hexdigest(), "rawBytes": len(content),
                "gzipSha256": hashlib.sha256(compressed).hexdigest(), "gzipBytes": len(compressed)} == expected, f"{name}: exact SHA/size differs")
    summary = json.loads((root / "receipt.json").read_text())
    receipt, report = read(root, "linux/receipt.json"), read(root, "linux/report.json")
    expect(summary["sourceCommit"] == receipt["sourceCommit"] == SOURCE_COMMIT, "Source commit differs")
    expect(summary["evidenceValid"] is True and receipt["valid"] is True and receipt["bindingsUnchanged"] is True, "Receipt/input validity differs")
    before = read(root, "linux/identity-before.json")
    expect(before == read(root, "linux/identity-after.json"), "Full before/after identities differ")
    built = obj(cast(Json, json.loads(gzip.decompress((repo / BUILD_RECORD).read_bytes()))), BUILD_RECORD)
    for field in ("source", "runtime", "archive", "python", "nativeLibraries", "leanVersion"):
        expect(before[field] == built[field], f"{field}: exact-source runtime build identity differs")
    expect(obj(before["runtime"], "linux/identity-before.json.runtime")["root"] == summary["runtime"] == RUNTIME, "Runtime path differs")
    for value in obj(report["runtime"], "linux/report.json.runtime").values():
        binding = obj(value, "linux/report.json.runtime entry")
        expect(binding["sha256"] == obj(obj(obj(before["runtime"], "linux/identity-before.json.runtime.files")["files"], "linux/identity-before.json.runtime.files")[cast(str, binding["path"])], "linux/identity-before.json.runtime.files")["sha256"], "Report executable binding differs from the exact installed runtime")
    for field in ("source", "runtime"):
        expect(len(obj(obj(before[field], f"linux/identity-before.json.{field}.files")["files"], f"linux/identity-before.json.{field}.files")) == COUNTS[field], f"{field}: complete file count differs")
    source = read(root, "source-manifest.json")
    expect(source["revision"] == SOURCE_COMMIT and obj(before["archive"], "linux/identity-before.json.archive")["sha256"] == source["archiveSha256"], "Public archive identity differs")
    files = obj(obj(before["source"], "linux/identity-before.json.source.files")["files"], "linux/identity-before.json.source.files")
    for name, value in obj(source["files"], "source-manifest.json.files").items():
        expected, actual = obj(value, f"source entry {name}"), obj(files[name], f"source entry {name}")
        expect(actual["link"] == expected["link"] if "link" in expected else {k: actual[k] for k in ("sha256", "bytes")} == expected, f"{name}: public source entry differs")
    helpers = read(root, "helper-manifest.json")
    for name, expected in helpers.items():
        content = raw(root, "helpers/" + name)
        expect({"sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)} == expected, f"{name}: helper identity differs")
        expect(obj(obj(obj(before["helpers"], f"helper entry {name}")["files"], f"helper entry {name}")[name], f"helper entry {name}")["sha256"] == obj(expected, f"helper entry {name}")["sha256"], f"{name}: actual helper differs")
    old, current = raw(root, "reviewed-driver.py"), raw(root, "helpers/t04c_capture.py")
    expect(old.replace(PRIOR_DRIVER_SOURCE.encode(), SOURCE_COMMIT.encode()) == current and old.count(PRIOR_DRIVER_SOURCE.encode()) == 1, "Reviewed driver changed beyond its source label")
    original_bytes = (repo / HISTORICAL_RECORD).read_bytes(); original = obj(cast(Json, json.loads(original_bytes)), HISTORICAL_RECORD)
    expect(hashlib.sha256(original_bytes).hexdigest() == obj(receipt["historicalReceipt"], "linux/receipt.json.historicalReceipt")["sha256"], "Historical v5 receipt SHA differs")
    for side in ("generic", "synthetic"):
        observed, prior = obj(report[side], f"{side} evidence"), obj(original[side], f"{side} evidence")
        expect(all(observed[field] == prior[field] for field in FIELDS) and observed["nativeReplayPassed"] is True, f"{side}: selected evidence/profile/verdict fields differ")
        encoded = json.dumps(observed["selectedIdentities"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        expect(hashlib.sha256(encoded).hexdigest() == observed["selectedIdentitiesSha256"], f"{side}: selected identity digest differs")
    expect(report["denominator"] == summary["fullDenominator"] == COUNTS["denominator"] and report["selectedDenominator"] == summary["selectedIdentities"] == COUNTS["selected"], "Complete/selected denominator differs")
    expect(report["counts"] == summary["modelCounts"] == {MODEL_CLASSIFICATION: COUNTS["selected"]}, "Unsupported-only verdict count differs")
    expect(report["policy"] == original["policy"] and report["policySha256"] == original["policySha256"], "Selection policy differs")
    measurement = obj(report["measurement"], "linux/report.json.measurement"); seconds = measurement["seconds"]
    expect(measurement["phase"] == MEASUREMENT_PHASE, "Fresh measured phase kind differs")
    expect(type(seconds) in (int, float) and TARGET <= cast(float, seconds) < PHASE_LIMIT, "Valid target-miss timing differs")
    expect(receipt["measurement"] == measurement and summary["phaseSeconds"] == seconds, "Original phase seconds differ")
    expect(receipt["phaseLimitSeconds"] == measurement["limitSeconds"] == summary["phaseLimitSeconds"] == PHASE_LIMIT, "120-second group/phase guard differs")
    expect(summary["underTarget"] == receipt["underTarget"] == (cast(float, seconds) < TARGET) is False and summary["taskStatus"] == "IN PROGRESS", "Target miss or task status changed")
    phase = read(root, "linux/phase-result.json")
    expect(phase == receipt["phase"] and phase["failure"] is None and phase["fixturesCleaned"] is True, "Phase completion/cleanup differs")
    start, end = stamp(phase["started"], "linux/phase-result.json.started"), stamp(phase["ended"], "linux/phase-result.json.ended")
    capture_start, capture_end = stamp(read(root, "linux/capture-start.json"), "linux/capture-start.json"), stamp(receipt["captureEnded"], "linux/receipt.json.captureEnded")
    expect(capture_start[0] < start[0] < end[0] < capture_end[0] and capture_start[1] < start[1] < end[1] < capture_end[1], "Actual capture/phase boundaries are out of order")
    expect(phase["started"] == summary["started"] == read(root, "linux/phase-start.json") and phase["ended"] == summary["ended"], "Original phase boundaries differ")
    outer = (end[0] - start[0]) / 1e9
    expect(outer == phase["outerPhaseSeconds"] == summary["outerPhaseSeconds"] and cast(float, seconds) <= outer < PHASE_LIMIT, "Outer report duration differs")
    expect(abs((end[1] - start[1]).total_seconds() - outer) < UTC_TOLERANCE, "UTC/monotonic durations differ")
    paths = cast(list[str], phase["fixturePaths"]); storage = cast(str, summary["storageRoot"])
    expect(len(paths) == len(set(paths)) == COUNTS["selected"] and all(Path(p).is_relative_to(storage) and Path(p).name == "case.db" for p in paths), "Actual unique fixture paths differ")
    for side in ("before", "after"):
        conditions = read(root, f"linux/conditions-{side}.json")
        expect(conditions == receipt["conditions" + side.title()] and conditions["storageRoot"] == storage and conditions["storageDevice"] == summary["storageDevice"], f"{side}: original storage observation differs")
        expect(f'"fstype": "{FILESYSTEM_TYPE}"' in cast(str, obj(conditions["filesystem"], f"linux/conditions-{side}.json.filesystem")["findmnt"]) and conditions["osFileCaches"] == CACHE_QUALIFICATION, f"{side}: filesystem/cache qualification differs")
    command, observation = read(root, "linux/commands/command-0000.json"), obj(receipt["command"], "linux/receipt.json.command")
    expect(command["returncode"] == observation["returncode"] == summary["exitCode"] == 0 and command["timed_out"] is False, "Original phase command failed or timed out")
    expect(all(command[k] == observation[k] for k in ("stdout", "stderr")) and command["elapsed"] == observation["elapsedSeconds"], "Original command streams/duration differ")
    stdout = obj(cast(Json, json.loads(cast(str, command["stdout"]))), "linux/commands/command-0000.json.stdout")
    expect(stdout["phaseCompleted"] is True and stdout["failure"] is None and stdout["measurement"] == measurement, "Original phase stdout differs from its report")
    arguments = cast(list[str], command["command"])
    expect(arguments[1:] == ["-B", str(Path(cast(str, obj(before["helpers"], "linux/identity-before.json.helpers")["root"])) / "t04c_capture.py"), "phase",
        cast(str, obj(before["source"], "linux/identity-before.json source or archive")["root"]), RUNTIME, str(Path(storage).parent), cast(str, obj(before["archive"], "linux/identity-before.json source or archive")["path"])], "Original report-driver arguments differ")
    expect(Path(arguments[0]).parent == Path(cast(str, obj(before["python"], "linux/identity-before.json.python")["path"])).parent, "Original pinned Python entrypoint differs")
    preflight = read(root, "linux/preflight.json")
    expect(preflight["resourceGuardPassed"] is True and preflight["fullSourceMatchesReviewedArchive"] is True and preflight["helperHashes"] == helpers, "Original guard/source/helper preflight differs")
    expect(read(root, "linux/host-activity-preflight.json")["projectBuildTestReplayNames"] == [], "Preflight project co-runner observation differs")
    originals = read(root, "original-manifest.json")
    expect(originals["storageEmpty"] is True and len(obj(originals["files"], "original-manifest.json.files")) == ORIGINAL_FILE_COUNT, "Later actual fixture cleanup or original inventory differs")
    for name, value in obj(originals["files"], "original-manifest.json.files").items():
        content = raw(root, "linux/" + name)
        expect({"sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)} == value, f"{name}: original remote bytes differ")


if __name__ == "__main__":
    validate(Path(__file__).parent)
    print("Validated the complete 184-case Linux receipt; target missed and task remains IN PROGRESS.")
