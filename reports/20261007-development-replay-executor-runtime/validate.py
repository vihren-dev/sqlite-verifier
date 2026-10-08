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
APPROVED_BUILD_COMMAND = ("nix-build", "build-support/default.nix", "-A", "conformance", "--no-out-link",
                          "--extra-experimental-features", "nix-command flakes")
"""Only the authorized pinned conformance build runs; the command contains no replay or test target."""
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
ARCHIVED_COMMAND_PATHS = {"linux/build/command-0000.json": "linux/commands/command-0000.json"}
"""Keep the original remote names while archival commands avoid the generated build-directory ignore rule."""


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
            "gzipSha256": hashlib.sha256(compressed).hexdigest(), "gzipBytes": len(compressed)} == expected, (
                f"{name}: original/compressed SHA and size differ. Compare raw-sha256.json with the retained original.")
    summary = json.loads((root / "receipt.json").read_text())
    assert summary["sourceRevision"] == SOURCE_REVISION and summary["ready"] is True, (
        f"receipt.json: sourceRevision must be {SOURCE_REVISION} and ready must be true. Compare the reviewed integration.")
    assert summary["acceptancePerformed"] is False, "receipt.json: acceptancePerformed must be false. Retain this as build-only evidence."
    for name, (filename, count) in CHECK_COUNTS.items():
        suites = ElementTree.fromstring(raw(root, "integration/" + filename)).findall("testsuite")
        assert sum(int(suite.attrib["tests"]) for suite in suites) == count == summary["checks"][name]["passed"], (
            f"{filename}: JUnit tests and receipt passed count must be {count}. Compare the original test output.")
        assert all(int(suite.attrib[field]) == 0 for suite in suites for field in ("failures", "errors", "skipped")), (
            f"{filename}: failures/errors/skipped must be zero. Inspect the original JUnit cases.")
    manifest = read(root, "source-manifest.json")
    assert manifest["revision"] == SOURCE_REVISION and len(manifest["files"]) == summary["sourceEntries"] == SOURCE_ENTRY_COUNT, (
        f"source-manifest.json: revision/count must be {SOURCE_REVISION}/{SOURCE_ENTRY_COUNT}. Compare the public archive.")
    assert manifest["archiveSha256"] == summary["archive"]["archiveSha256"], "source-manifest.json: archiveSha256 differs. Compare the archive receipt."
    assert manifest["archiveBytes"] == summary["archive"]["archiveBytes"], "source-manifest.json: archiveBytes differs. Compare the archive receipt."
    headroom = raw(root, "integration/headroom-review-log.jsonl").splitlines(keepends=True)
    executor = raw(root, "integration/executor-review-log.jsonl").splitlines(keepends=True)
    pending = raw(root, "integration/pending-readiness-review.jsonl").splitlines(keepends=True)
    merged_bytes = raw(root, "integration/merged-review-log.jsonl")
    merged = merged_bytes.splitlines(keepends=True)
    assert len(merged) == JOURNAL_ROWS["merged"] and Counter(merged)[pending[0]] == JOURNAL_ROWS["pending"], (
        f"merged-review-log.jsonl: require {JOURNAL_ROWS['merged']} rows and {JOURNAL_ROWS['pending']} pending review. Compare the exact saved journals.")
    for original in (headroom, executor, headroom + pending):
        assert subsequence(original, merged) and not (Counter(original) - Counter(merged)), (
            "merged-review-log.jsonl: original order or row occurrences differ. Compare both saved journals and the pending row.")
    assert not (Counter(merged) - Counter(headroom + executor + pending)), (
        "merged-review-log.jsonl: contains an unrecorded row occurrence. Compare the exact saved originals.")
    original_hashes = read(root, "linux/original-manifest.json")
    for name, expected in original_hashes.items():
        archive_name = ARCHIVED_COMMAND_PATHS.get(name, name)
        payload = raw(root, "linux/" + archive_name)
        assert {"sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)} == expected, (
            f"{name}: original remote SHA or size differs. Compare linux/original-manifest.json.")
    journal = read(root, "integration/journal-merge.json")
    assert hashlib.sha256(merged_bytes).hexdigest() == journal["sha256"], (
        "journal-merge.json: sha256 differs from archived merged bytes. Compare the original journal merge.")
    source_comparison = read(root, "integration/source-comparison.json")
    assert all(source_comparison[key] is True for key in (
        "onlyApprovedT04Differences", "frozenAndWorkloadUnchanged", "pendingWorkingCopyNotAncestor")), (
            "source-comparison.json: publication/frozen/ancestry checks must all pass. Repeat only the read-only revision comparison.")
    for platform, file_count in RUNTIME_FILE_COUNTS.items():
        prefix = "darwin/" if platform == "darwin" else "linux/linux/"
        before, after = read(root, prefix + "inputs-before.json"), read(root, prefix + "inputs-after.json")
        identity = read(root, prefix + "identity-after.json")
        runtime_before = read(root, prefix + "runtime-before.json")
        assert before == after and runtime_before == identity["runtime"], f"{prefix}: input/runtime identities differ. Compare complete before/after manifests."
        assert len(identity["runtime"]["files"]) == file_count, f"{prefix}identity-after.json: require {file_count} runtime files. Compare the original inventory."
        assert identity["source"] == before["source"], f"{prefix}identity-after.json: source differs. Compare inputs-before.json."
        assert identity["helpers"] == before["helpers"] and identity["python"] == before["python"], (
            f"{prefix}identity-after.json: helper/Python identities differ. Compare inputs-before.json.")
        assert identity["nativeLibraries"] == before["declaredNativeLibraries"], f"{prefix}identity-after.json: native libraries differ. Compare inputs-before.json."
        assert PINNED_LEAN_VERSION in identity["leanVersion"] and PINNED_PYTHON_VERSION in identity["python"]["version"], (
            f"{prefix}identity-after.json: Lean/Python must be {PINNED_LEAN_VERSION}/{PINNED_PYTHON_VERSION}. Compare the pinned environment.")
        for name, expected in manifest["files"].items():
            observed = before["source"]["files"][name]
            if "link" in expected:
                assert observed["link"] == expected["link"], f"{prefix}{name}: source link differs. Compare the public source manifest."
            else:
                assert {key: observed[key] for key in ("sha256", "bytes")} == expected, f"{prefix}{name}: source SHA/size differs. Compare the public source manifest."
        assert before["source"]["files"]["reviews/log.jsonl"]["sha256"] == journal["sha256"], f"{prefix}reviews/log.jsonl: SHA differs. Compare journal-merge.json."
        assert len(headroom) == journal["headroomRows"] == JOURNAL_ROWS["headroom"], f"journal-merge.json: require {JOURNAL_ROWS['headroom']} headroom rows. Compare its saved original."
        assert len(executor) == journal["executorRows"] == JOURNAL_ROWS["executor"], f"journal-merge.json: require {JOURNAL_ROWS['executor']} executor rows. Compare its saved original."
        assert len(pending) == journal["pendingRows"] == JOURNAL_ROWS["pending"], f"journal-merge.json: require {JOURNAL_ROWS['pending']} pending row. Compare its saved original."
        assert journal["mergedRows"] == JOURNAL_ROWS["merged"], f"journal-merge.json: require {JOURNAL_ROWS['merged']} merged rows. Compare the archived merged journal."
        assert journal["parentOrdersAndMultiplicitiesRetained"] is True, "journal-merge.json: order/multiplicity check must pass. Compare exact journal rows."
        expected_runtime = read(root, prefix + "expected-runtime.json")
        receipt = read(root, prefix + "receipt.json")
        assert receipt["valid"] is True and receipt["buildReturncode"] == 0 and receipt["replayInvocations"] == 0, (
            f"{prefix}receipt.json: require valid, exit zero and no replay. Compare the original build-only output.")
        assert receipt["sourceRevision"] == SOURCE_REVISION and receipt["buildLimitSeconds"] == BUILD_LIMIT_SECONDS, (
            f"{prefix}receipt.json: source/build bound must be {SOURCE_REVISION}/{BUILD_LIMIT_SECONDS}. Compare the authorized source and command.")
        assert receipt["runtime"] == expected_runtime["path"] == identity["runtime"]["root"], f"{prefix}receipt.json: runtime differs. Compare expected-runtime.json and inventory."
        reported = summary["platforms"][platform]
        assert reported["runtime"] == receipt["runtime"] and reported["runtimeFiles"] == file_count, f"receipt.json platforms.{platform}: runtime/count differs. Compare the original inventory."
        assert reported["sourceFiles"] == summary["sourceEntries"] and reported["existedBefore"] is True, f"receipt.json platforms.{platform}: source/count/cache state differs. Compare original observations."
        assert reported["runtimeBeforeEqualsAfter"] is True and reported["sourceInputsBeforeEqualsAfter"] is True, f"receipt.json platforms.{platform}: identity checks must pass. Compare before/after inventories."
        assert reported["replayInvocations"] == 0 and reported["exitCode"] == 0, f"receipt.json platforms.{platform}: require no replay and exit zero. Compare original commands."
        assert reported["leanVersion"] == identity["leanVersion"] and reported["python"] == identity["python"], f"receipt.json platforms.{platform}: compiler/Python differs. Compare identity-after.json."
        assert reported["nativeLibraries"] == identity["nativeLibraries"], f"receipt.json platforms.{platform}: native library identities differ. Compare identity-after.json."
        assert expected_runtime["existedBefore"] is True and read(root, prefix + "guard.json")["passed"] is True, f"{prefix}: cached output and successful guard required. Compare original preflight."
        start, end = read(root, prefix + "build-start.json"), read(root, prefix + "build-result.json")
        assert end["returncode"] == 0 and end["timedOut"] is False, f"{prefix}build-result.json: require exit zero without timeout. Inspect original build streams."
        assert start["monotonicNs"] < end["ended"]["monotonicNs"], f"{prefix}build-result.json: monotonic end must follow start. Compare original boundaries."
        assert datetime.fromisoformat(start["utc"]) < datetime.fromisoformat(end["ended"]["utc"]), f"{prefix}build-result.json: UTC end must follow start. Compare original boundaries."
        command = read(root, prefix + "commands/command-0000.json")
        assert command["returncode"] == 0 and command["timed_out"] is False, f"{prefix}commands/command-0000.json: require exit zero without timeout. Inspect original streams."
        assert command["command"] == list(APPROVED_BUILD_COMMAND), f"{prefix}commands/command-0000.json: build command differs. Compare APPROVED_BUILD_COMMAND."


if __name__ == "__main__":
    validate(Path(__file__).parent)
    print("Validated exact native runtime readiness; no replay or acceptance performed.")
