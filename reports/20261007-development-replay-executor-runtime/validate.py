"""Check retained build readiness without compiling, loading a corpus or performing replay."""

from collections import Counter
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path
from typing import TypeAlias
from xml.etree import ElementTree

Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]
SOURCE_REVISION = "c3e8f5186e2865b5cdc0ea5af1a9d0924531752a"
"""The integration was reviewed before either authorized native build."""
BUILD_LIMIT_SECONDS = 900
"""Retain the configured conformance build bound independently of receipt fields."""
RUNTIME_FILE_COUNTS = {"darwin": 17897, "linux": 17936}
"""Count every installed output file, including resolved links, on each native platform."""
SOURCE_ENTRY_COUNT = 1113
"""Require the complete exported source inventory rather than accepting a smaller copied tree."""
CHECK_COUNTS = {"changedTests": ("changed-tests.xml", 92), "routingTests": ("routing-tests.xml", 56)}
"""Bind reported passing checks to their original JUnit suites, including zero skipped checks."""
JOURNAL_ROWS = {"headroom": 110, "executor": 161, "pending": 1, "merged": 208}
"""Retain exact observed journal row counts alongside their order and occurrence checks."""
PINNED_LEAN_VERSION = "4.34.1"
"""Both approved publication builds use this actual compiler release."""
PINNED_PYTHON_VERSION = "3.14.7"
"""The same locked environment supplies both native capture interpreters."""


def read(root: Path, name: str) -> Json:
    """Read one already hash-checked original JSON artifact."""
    return json.loads(gzip.decompress((root / (name + ".gz")).read_bytes()))


def raw(root: Path, name: str) -> bytes:
    """Keep journal bytes exact so repeated rows cannot disappear through normalization."""
    return gzip.decompress((root / (name + ".gz")).read_bytes())


def subsequence(original: list[bytes], merged: list[bytes]) -> bool:
    """Preserve original row order and occurrences rather than comparing only sets."""
    remaining = iter(merged)
    return all(any(row == candidate for candidate in remaining) for row in original)


def validate(root: Path) -> None:
    """Require exact originals, ordered journals and complete unchanged build inputs and outputs."""
    hashes = json.loads((root / "raw-sha256.json").read_text())
    for name, expected in hashes.items():
        compressed = (root / name).read_bytes()
        payload = gzip.decompress(compressed)
        assert {"rawSha256": hashlib.sha256(payload).hexdigest(), "rawBytes": len(payload),
            "gzipSha256": hashlib.sha256(compressed).hexdigest(), "gzipBytes": len(compressed)} == expected, name
    summary = json.loads((root / "receipt.json").read_text())
    assert summary["sourceRevision"] == SOURCE_REVISION and summary["ready"] is True
    assert summary["acceptancePerformed"] is False
    for name, (filename, count) in CHECK_COUNTS.items():
        suites = ElementTree.fromstring(raw(root, "integration/" + filename)).findall("testsuite")
        assert sum(int(suite.attrib["tests"]) for suite in suites) == count == summary["checks"][name]["passed"]
        assert all(int(suite.attrib[field]) == 0 for suite in suites for field in ("failures", "errors", "skipped"))
    manifest = read(root, "source-manifest.json")
    assert manifest["revision"] == SOURCE_REVISION and len(manifest["files"]) == summary["sourceEntries"] == SOURCE_ENTRY_COUNT
    assert manifest["archiveSha256"] == summary["archive"]["archiveSha256"]
    assert manifest["archiveBytes"] == summary["archive"]["archiveBytes"]
    headroom = raw(root, "integration/headroom-review-log.jsonl").splitlines(keepends=True)
    executor = raw(root, "integration/executor-review-log.jsonl").splitlines(keepends=True)
    pending = raw(root, "integration/pending-readiness-review.jsonl").splitlines(keepends=True)
    merged_bytes = raw(root, "integration/merged-review-log.jsonl")
    merged = merged_bytes.splitlines(keepends=True)
    assert len(merged) == JOURNAL_ROWS["merged"] and Counter(merged)[pending[0]] == JOURNAL_ROWS["pending"]
    for original in (headroom, executor, headroom + pending):
        assert subsequence(original, merged) and not (Counter(original) - Counter(merged))
    assert not (Counter(merged) - Counter(headroom + executor + pending))
    original_hashes = read(root, "linux/original-manifest.json")
    for name, expected in original_hashes.items():
        payload = raw(root, "linux/" + name)
        assert {"sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)} == expected, name
    journal = read(root, "integration/journal-merge.json")
    assert hashlib.sha256(merged_bytes).hexdigest() == journal["sha256"]
    source_comparison = read(root, "integration/source-comparison.json")
    assert all(source_comparison[key] is True for key in (
        "onlyApprovedT04Differences", "frozenAndWorkloadUnchanged", "pendingWorkingCopyNotAncestor"))
    for platform, file_count in RUNTIME_FILE_COUNTS.items():
        prefix = "darwin/" if platform == "darwin" else "linux/linux/"
        before, after = read(root, prefix + "inputs-before.json"), read(root, prefix + "inputs-after.json")
        identity = read(root, prefix + "identity-after.json")
        runtime_before = read(root, prefix + "runtime-before.json")
        assert before == after and runtime_before == identity["runtime"]
        assert len(identity["runtime"]["files"]) == file_count
        assert identity["source"] == before["source"]
        assert identity["helpers"] == before["helpers"] and identity["python"] == before["python"]
        assert identity["nativeLibraries"] == before["declaredNativeLibraries"]
        assert PINNED_LEAN_VERSION in identity["leanVersion"] and PINNED_PYTHON_VERSION in identity["python"]["version"]
        for name, expected in manifest["files"].items():
            observed = before["source"]["files"][name]
            if "link" in expected:
                assert observed["link"] == expected["link"], name
            else:
                assert {key: observed[key] for key in ("sha256", "bytes")} == expected, name
        assert before["source"]["files"]["reviews/log.jsonl"]["sha256"] == journal["sha256"]
        assert len(headroom) == journal["headroomRows"] == JOURNAL_ROWS["headroom"]
        assert len(executor) == journal["executorRows"] == JOURNAL_ROWS["executor"]
        assert len(pending) == journal["pendingRows"] == JOURNAL_ROWS["pending"]
        assert journal["mergedRows"] == JOURNAL_ROWS["merged"]
        assert journal["parentOrdersAndMultiplicitiesRetained"] is True
        expected_runtime = read(root, prefix + "expected-runtime.json")
        receipt = read(root, prefix + "receipt.json")
        assert receipt["valid"] is True and receipt["buildReturncode"] == 0 and receipt["replayInvocations"] == 0
        assert receipt["sourceRevision"] == SOURCE_REVISION and receipt["buildLimitSeconds"] == BUILD_LIMIT_SECONDS
        assert receipt["runtime"] == expected_runtime["path"] == identity["runtime"]["root"]
        reported = summary["platforms"][platform]
        assert reported["runtime"] == receipt["runtime"] and reported["runtimeFiles"] == file_count
        assert reported["sourceFiles"] == summary["sourceEntries"] and reported["existedBefore"] is True
        assert reported["runtimeBeforeEqualsAfter"] is True and reported["sourceInputsBeforeEqualsAfter"] is True
        assert reported["replayInvocations"] == 0 and reported["exitCode"] == 0
        assert reported["leanVersion"] == identity["leanVersion"] and reported["python"] == identity["python"]
        assert reported["nativeLibraries"] == identity["nativeLibraries"]
        assert expected_runtime["existedBefore"] is True and read(root, prefix + "guard.json")["passed"] is True
        start, end = read(root, prefix + "build-start.json"), read(root, prefix + "build-result.json")
        assert end["returncode"] == 0 and end["timedOut"] is False
        assert start["monotonicNs"] < end["ended"]["monotonicNs"]
        assert datetime.fromisoformat(start["utc"]) < datetime.fromisoformat(end["ended"]["utc"])
        command = read(root, prefix + "build/command-0000.json")
        assert command["returncode"] == 0 and command["timed_out"] is False
        assert command["command"] == ["nix-build", "build-support/default.nix", "-A", "conformance", "--no-out-link",
                                      "--extra-experimental-features", "nix-command flakes"]


if __name__ == "__main__":
    validate(Path(__file__).parent)
    print("Validated exact native runtime readiness; no replay or acceptance performed.")
