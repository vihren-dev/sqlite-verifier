"""Check retained stage wall and parent/child CPU observations without replay."""

from __future__ import annotations

from datetime import datetime, timedelta
import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias, cast

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / "20261007-development-replay-headroom-acceptance"
#: The reviewed source measured in both the prior fresh phase and this diagnostic.
SOURCE_COMMIT = "5d15607fdf78d0a209b539ca158939739b54d377"
#: This selected population stays fixed while every frozen binding is checked.
SELECTED_IDENTITIES = 184
#: The owner-approved process-group guard also bounds this diagnostic.
PHASE_LIMIT = 120
#: Parent-stage counts for this one full development report, including both bindings.
STAGE_CALLS = {"runtime_binding": 1, "load": 1, "bound_records": 1, "select": 1,
               "replay_native_cases": 1, "checked_replay": 2, "binding": 2}
#: CPU of the observing parent and direct children reaped in each observed call.
CPU_FIELDS = ("parentUserSeconds", "parentSystemSeconds", "childrenUserSeconds", "childrenSystemSeconds")


def mapping(value: Json) -> dict[str, Json]:
    """Narrow JSON to an object so named observation fields can be checked."""
    assert isinstance(value, dict), value
    return value


def decode(content: bytes) -> dict[str, Json]:
    """Read a retained JSON object without executing any helper."""
    return mapping(cast(Json, json.loads(content)))


def raw(name: str) -> bytes:
    """Read the exact original bytes of one immutable compressed artifact."""
    return gzip.decompress((ROOT / (name + ".gz")).read_bytes())


def document(name: str) -> dict[str, Json]:
    """Read structured evidence for independent result and counter checks."""
    return decode(raw(name))


def sha(content: bytes) -> str:
    """Bind compressed transport and original observations independently."""
    return hashlib.sha256(content).hexdigest()


def number(value: Json) -> int | float:
    """Require a real counter or duration, excluding JSON booleans."""
    assert type(value) in (int, float), value
    return cast(int | float, value)


def validate() -> None:
    """Check full unchanged evidence and recompute every recorded stage total."""
    summary = decode((ROOT / "receipt.json").read_bytes())
    manifest = decode((ROOT / "raw-sha256.json").read_bytes())
    assert set(manifest) == {str(path.relative_to(ROOT)) for path in ROOT.rglob("*.gz")}
    assert len(manifest) == summary["rawArtifacts"]
    for name, fields in manifest.items():
        expected = mapping(fields)
        packed = (ROOT / name).read_bytes()
        content = gzip.decompress(packed)
        assert sha(packed) == expected["sha256"] and sha(content) == expected["uncompressedSha256"], name
        assert len(content) == expected["uncompressedBytes"], name
    receipt = document("diagnostic/receipt.json")
    assert summary["diagnosticOnly"] is True and receipt["diagnosticOnly"] is True
    assert summary["productionChanges"] is False and summary["newConformanceBuild"] is False
    assert summary["actualInstrumentedPhases"] == 1 and summary["completedExit"] == 0
    assert summary["taskStatus"] == "IN PROGRESS" and summary["evidenceValid"] is True and receipt["valid"] is True
    assert receipt["sourceCommit"] == summary["sourceCommit"] == SOURCE_COMMIT
    before, after = document("diagnostic/identity-before.json"), document("diagnostic/identity-after.json")
    assert before == after
    previous = decode(gzip.decompress((PREVIOUS / "linux/identity-before.json.gz").read_bytes()))
    assert {key: value for key, value in before.items() if key != "helpers"} == {
        key: value for key, value in previous.items() if key != "helpers"}
    assert mapping(before["runtime"])["root"] == summary["runtime"]
    helpers = mapping(mapping(before["helpers"])["files"])
    declared = mapping(document("helper-manifest.json")["helpers"])
    assert set(helpers) == set(declared)
    for name, fields in helpers.items():
        content = raw("helpers/" + name)
        assert sha(content) == mapping(fields)["sha256"] == mapping(declared[name])["sha256"]
        assert len(content) == mapping(declared[name])["bytes"]
    preflight = document("remote-preflight.json")
    assert preflight["phaseStarted"] is False
    assert all(value is True for value in mapping(preflight["helperChecks"]).values())
    assert all(value is True for value in mapping(preflight["unchangedFromFreshReceipt"]).values())
    assert preflight["identity"] == before
    report = document("diagnostic/report.json")
    prior_report = decode(gzip.decompress((PREVIOUS / "linux/report.json.gz").read_bytes()))
    assert {key: value for key, value in report.items() if key != "measurement"} == {
        key: value for key, value in prior_report.items() if key != "measurement"}
    assert report["selectedDenominator"] == summary["selectedIdentities"] == SELECTED_IDENTITIES
    assert report["denominator"] == summary["fullDenominator"]
    measurement = mapping(report["measurement"])
    assert measurement == receipt["measurement"]
    assert measurement["seconds"] == summary["instrumentedPhaseSeconds"]
    assert measurement["limitSeconds"] == summary["phaseLimitSeconds"] == PHASE_LIMIT
    assert 0 < number(measurement["seconds"]) < PHASE_LIMIT
    phase = document("diagnostic/phase-result.json")
    assert phase == receipt["phase"] and phase["failure"] is None and phase["fixturesCleaned"] is True
    assert phase["started"] == document("diagnostic/phase-start.json") == summary["started"]
    assert phase["ended"] == summary["ended"]
    started, ended = mapping(phase["started"]), mapping(phase["ended"])
    start_ns, end_ns = number(started["monotonicNs"]), number(ended["monotonicNs"])
    assert (end_ns - start_ns) / 1e9 == phase["outerPhaseSeconds"] == summary["outerPhaseSeconds"]
    for fields in (started, ended):
        assert isinstance(fields["utc"], str) and datetime.fromisoformat(fields["utc"]).utcoffset() == timedelta(0)
    paths = phase["fixturePaths"]
    conditions = document("diagnostic/conditions-before.json")
    storage = conditions["storageRoot"]
    assert isinstance(storage, str) and isinstance(paths, list)
    assert len(paths) == len(set(cast(list[str], paths))) == SELECTED_IDENTITIES
    assert all(isinstance(path, str) and Path(path).is_relative_to(storage) and Path(path).name == "case.db" for path in paths)
    after_conditions = document("diagnostic/conditions-after.json")
    assert conditions == receipt["conditionsBefore"] and after_conditions == receipt["conditionsAfter"]
    assert conditions["storageDevice"] == after_conditions["storageDevice"]
    assert conditions["storageRoot"] == after_conditions["storageRoot"]
    assert '"fstype": "ext4"' in str(mapping(conditions["filesystem"])["findmnt"])
    command = document("diagnostic/commands/command-0000.json")
    assert command["returncode"] == 0 and command["timed_out"] is False
    observation = mapping(receipt["command"])
    assert observation["returncode"] == 0 and observation["timedOut"] is False
    assert all(command[key] == observation[key] for key in ("stdout", "stderr"))
    assert command["elapsed"] == observation["elapsedSeconds"]
    assert isinstance(command["stdout"], str) and decode(command["stdout"].encode())["measurement"] == measurement
    stages = document("diagnostic/stage-observations.json")
    assert set(stages) == set(STAGE_CALLS)
    intervals: list[tuple[int | float, int | float]] = []
    for name, value in stages.items():
        assert isinstance(value, list) and len(value) == STAGE_CALLS[name]
        calls = [mapping(call) for call in value]
        for call in calls:
            first, last = number(call["startedMonotonicNs"]), number(call["endedMonotonicNs"])
            assert start_ns <= first < last <= end_ns and call["failureType"] is None
            assert (last - first) / 1e9 == call["wallSeconds"]
            metrics = mapping(call["metricsDelta"])
            assert set(metrics) == set(CPU_FIELDS) and all(number(metrics[field]) >= 0 for field in CPU_FIELDS)
            intervals.append((first, last))
        assert mapping(summary["stageTotals"])[name] == {"calls": len(calls),
            "wallSeconds": sum(number(call["wallSeconds"]) for call in calls),
            **{field: sum(number(mapping(call["metricsDelta"])[field]) for call in calls) for field in CPU_FIELDS}}
    ordered = sorted(intervals)
    assert all(first[1] <= second[0] for first, second in zip(ordered, ordered[1:]))
    retrieval = document("retrieval-manifest.json")
    assert retrieval["nativeStorageEntries"] == []
    for name, fields in mapping(retrieval["files"]).items():
        content = raw(name)
        assert sha(content) == mapping(fields)["sha256"] and len(content) == mapping(fields)["bytes"]
    print("Diagnostic hashes, unchanged 184-case evidence, actual paths and all parent/child stage counters pass.")


if __name__ == "__main__":
    validate()
