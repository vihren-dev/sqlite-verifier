"""Check original load-only profile evidence without loading a corpus or replaying SQL."""

from __future__ import annotations

from datetime import datetime, timedelta
import gzip
import hashlib
import json
from pathlib import Path
import pstats
from tempfile import TemporaryDirectory
from typing import TypeAlias, cast

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
FunctionKey: TypeAlias = tuple[str, int, str]
ProfileEntry: TypeAlias = tuple[int, int, float, float, dict[FunctionKey, tuple[int, int, float, float]]]
ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / "20261007-development-replay-headroom-acceptance"
#: Reviewed source used by the fresh phase and both subsequent diagnostics.
SOURCE_COMMIT = "5d15607fdf78d0a209b539ca158939739b54d377"
#: Every generic frozen-v5 case must be loaded and bound; synthetic records are outside this load.
LOADED_RECORD_COUNT = 4376
#: The owner-approved process-group bound also applies to this load-only diagnostic.
PHASE_LIMIT = 120
#: These identities can compare directly with the prior fresh receipt despite new helper files.
UNCHANGED_IDENTITY_FIELDS = ("source", "python", "archive")
#: Loading must not invoke native evidence, worker replay, or compiled-model execution.
FORBIDDEN_FUNCTIONS = {"native_replay", "replay_native_cases", "record_sql", "compiled_many", "checked_replay"}
#: The authorized parent function loads every frozen binding without replay or selection.
AUTHORIZED_LOAD_FUNCTION = ("/conformance/corpus.py", "load")
#: One profiled invocation is allowed; reading pstats never repeats it.
AUTHORIZED_LOAD_INVOCATIONS = 1


def mapping(value: Json) -> dict[str, Json]:
    """Narrow JSON to an object so observation fields can be checked."""
    assert isinstance(value, dict), value
    return value


def decode(content: bytes) -> dict[str, Json]:
    """Read a structured original observation without executing its helper."""
    return mapping(cast(Json, json.loads(content)))


def raw(name: str) -> bytes:
    """Recover exact original bytes after their compressed transport is checked."""
    return gzip.decompress((ROOT / (name + ".gz")).read_bytes())


def document(name: str) -> dict[str, Json]:
    """Read one retained JSON object for independent binding and result checks."""
    return decode(raw(name))


def sha(content: bytes) -> str:
    """Bind original and compressed artifact bytes separately."""
    return hashlib.sha256(content).hexdigest()


def canonical(value: Json) -> bytes:
    """Recompute profile identity with the canonical JSON definition used by the source."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def validate() -> None:
    """Verify all-binding load provenance and original function/caller counters."""
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
    receipt, result = document("diagnostic/receipt.json"), document("diagnostic/load-result.json")
    assert summary["sourceCommit"] == receipt["sourceCommit"] == SOURCE_COMMIT
    assert summary["actualLoadInvocations"] == AUTHORIZED_LOAD_INVOCATIONS and summary["completedExit"] == 0
    assert summary["productionChanges"] is False and summary["newRuntimeBuild"] is False
    assert summary["nativeReplayOrModelExecution"] is False and summary["taskStatus"] == "IN PROGRESS"
    assert summary["diagnosticOnly"] is True and receipt["diagnosticOnly"] is True and result["diagnosticOnly"] is True
    assert result["kind"] == receipt["kind"] == summary["kind"] == "instrumented-load-only"
    assert result["failure"] is None and receipt["profileRetained"] is True and receipt["bindingsUnchanged"] is True
    assert receipt["phaseLimitSeconds"] == summary["phaseLimitSeconds"] == PHASE_LIMIT
    for key in ("instrumentedLoadSeconds", "parentUserSeconds", "parentSystemSeconds", "started", "ended", "loadedRecordCount", "corpusVersion", "casesSha256"):
        assert result[key] == summary[key], key
    start, end = mapping(result["started"]), mapping(result["ended"])
    assert result["started"] == document("diagnostic/load-start.json")
    assert isinstance(start["monotonicNs"], int) and isinstance(end["monotonicNs"], int)
    duration = (end["monotonicNs"] - start["monotonicNs"]) / 1e9
    assert duration == result["instrumentedLoadSeconds"] and 0 < duration < PHASE_LIMIT
    for stamp in (start, end):
        assert isinstance(stamp["utc"], str) and datetime.fromisoformat(stamp["utc"]).utcoffset() == timedelta(0)
    before = document("diagnostic/identity-before.json")
    assert before == document("diagnostic/identity-after.json") == document("preflight.json")["identity"]
    old = decode(gzip.decompress((PREVIOUS / "linux/identity-before.json.gz").read_bytes()))
    assert all(before[field] == old[field] for field in UNCHANGED_IDENTITY_FIELDS)
    files = mapping(mapping(before["source"])["files"])
    frozen = mapping(mapping(before["frozenV5"])["files"])
    assert frozen == {name.removeprefix("conformance/corpus-v5/"): fields for name, fields in files.items() if name.startswith("conformance/corpus-v5/")}
    declared = mapping(document("helper-manifest-final.json")["helpers"])
    helpers = mapping(mapping(before["helpers"])["files"])
    assert set(helpers) == set(declared)
    for name, fields in helpers.items():
        content = raw("helpers/" + name)
        assert sha(content) == mapping(fields)["sha256"] == mapping(declared[name])["sha256"]
    loaded = document("diagnostic/loaded-manifest.json")
    assert result["loadedRecordCount"] == loaded["recordedCases"] == LOADED_RECORD_COUNT
    assert result["casesSha256"] == loaded["casesSha256"] and result["corpusVersion"] == loaded["corpusVersion"]
    binding = document("diagnostic/loaded-binding.json")
    assert binding["manifestSha256"] == mapping(frozen["manifest.json"])["sha256"]
    assert binding["declaredProfiles"] == loaded["executionProfiles"]
    assert sha(canonical(loaded["executionProfiles"])) == binding["profileBindingSha256"]
    assert {canonical(profile) for profile in cast(list[Json], binding["profiles"])} == {canonical(profile) for profile in cast(list[Json], loaded["executionProfiles"])}
    names = binding["names"]
    assert isinstance(names, list) and len(names) == len(set(cast(list[str], names))) == LOADED_RECORD_COUNT
    assert binding["byPart"] == loaded["byPart"]
    command = document("diagnostic/commands/command-0000.json")
    observation = mapping(receipt["command"])
    assert command["returncode"] == observation["returncode"] == 0
    assert command["timed_out"] is False and observation["timedOut"] is False
    assert all(command[key] == observation[key] for key in ("stdout", "stderr"))
    assert isinstance(command["stdout"], str) and decode(command["stdout"].encode()) == result
    with TemporaryDirectory() as temporary:
        path = Path(temporary) / "original.pstats"
        path.write_bytes(raw("diagnostic/load.pstats"))
        statistics = pstats.Stats(str(path))
    functions = cast(dict[FunctionKey, ProfileEntry], statistics.stats)
    assert statistics.total_tt == summary["profileTotalSeconds"]
    load_keys = [key for key in functions if key[0].endswith(AUTHORIZED_LOAD_FUNCTION[0]) and key[2] == AUTHORIZED_LOAD_FUNCTION[1]]
    assert len(load_keys) == 1 and functions[load_keys[0]][:2] == (AUTHORIZED_LOAD_INVOCATIONS, AUTHORIZED_LOAD_INVOCATIONS)
    assert not any(key[2] in FORBIDDEN_FUNCTIONS for key in functions)
    callers = document("callers-derived.json")
    for name, fields in callers.items():
        key = next(key for key in functions if str(key) == name)
        entry = functions[key]
        expected = mapping(fields)
        assert [entry[0], entry[1], entry[2], entry[3]] == [expected[field] for field in ("primitiveCalls", "totalCalls", "selfSeconds", "cumulativeSeconds")]
        assert {str(caller): list(metrics) for caller, metrics in entry[4].items()} == expected["callers"]
    retrieval = document("retrieval-manifest.json")
    for name, fields in mapping(retrieval["files"]).items():
        content = raw(name)
        assert sha(content) == mapping(fields)["sha256"] and len(content) == mapping(fields)["bytes"]
    assert document("transfer-preflight-failure.json")["loadStarted"] is False
    print(f"One all-binding {LOADED_RECORD_COUNT:,}-record load, unchanged hashes/profiles and original pstats/callers pass.")


if __name__ == "__main__":
    validate()
