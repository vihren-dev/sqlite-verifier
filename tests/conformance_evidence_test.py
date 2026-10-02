"""Ordinary loading refuses edited optional freeze evidence without requiring source acquisition."""

import gzip
import json
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.corpus import load
from conformance.corpus_evidence import FEATURE_LABEL_VIEWS, feature_counts
from conformance.freeze_corpus import freeze
from conformance.freeze_validation import digest
from conformance.native_storage import serialized, shared_record
from tests.conformance_freeze_test import capture, save

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


@pytest.fixture
def frozen(capture: tuple[Path, Path, dict[str, Json], dict[str, Json]],
           tmp_path: Path) -> tuple[Path, dict[str, Json]]:
    """Use the actual finalizer so positive evidence binding includes its exact publication layout."""
    directory, upstream, report, record = capture
    file = next(file for file in report["files"] if file["file"] == "check.test")
    reason = "native acquisition: prefix results differ from Tcl execution: filesystem path observation"
    file.update(runtimeAssertions=1, reasons={reason: 1}, instances=[
        {"id": "mismatch", "occurrence": 0, "result": reason, "exclusions": [reason],
         "tclResultPrecision": {"values": [0], "successfulCalls": 1}}])
    save(directory, report, shared_record(record))
    proof = tmp_path / "proof.txt"
    proof.write_text("Independent native and Tcl path observations.\n")
    ledger = {"ledgerVersion": 1, "extractionSha256": digest((directory / "manifest.json").read_bytes()),
              "entries": [{"file": "check.test", "id": "mismatch", "occurrence": 0,
                           "cause": "filesystem path observation", "evidence": [{"path": "proof.txt", "sha256": digest(proof.read_bytes())}]}]}
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_bytes(serialized(ledger))
    output = tmp_path / "frozen"
    return output, freeze(directory, output, upstream=upstream, fidelity_ledger=ledger_path)


def test_optional_evidence_survives_actual_load(frozen: tuple[Path, dict[str, Json]]) -> None:
    """A complete finalizer output loads with acquisition, named causes and retained proofs intact."""
    directory, manifest = frozen
    actual, records = load(directory)
    assert actual == manifest and len(records) == 5
    assert actual["fidelityLedger"]["mismatches"] == 1


@pytest.mark.parametrize("damage", [None, "case-credit", "duplicate", "boolean", "partial"])
def test_scoped_label_counts_bind_actual_records(frozen: tuple[Path, dict[str, Json]], damage: str | None) -> None:
    """File annotations cannot be rebound as measured case-feature credit through manifest edits."""
    directory, manifest = frozen
    _actual, records = load(directory)
    manifest.update(feature_counts(records))
    label = next(iter(manifest["bySourceFileLabel"]))
    if damage == "case-credit":
        manifest["byCaseFeatureLabel"][label] = manifest["bySourceFileLabel"].pop(label)
    elif damage == "duplicate": manifest["bySourceFileLabel"][label] += 1
    elif damage == "boolean": manifest["bySourceFileLabel"][label] = True
    elif damage == "partial": del manifest["byUnscopedFeatureLabel"]
    (directory / "manifest.json").write_bytes(serialized(manifest))
    if damage is None:
        loaded, _records = load(directory)
        assert all(loaded[view] == feature_counts(records)[view] for view in FEATURE_LABEL_VIEWS)
    else:
        with pytest.raises(ValueError, match="feature label counts"):
            load(directory)


@pytest.mark.parametrize("damage", ["extraction-bytes", "extraction-uncompressed", "extraction-path", "extraction-count",
    "ledger-bytes", "ledger-uncompressed", "ledger-symlink", "ledger-version", "ledger-extraction", "ledger-reference",
    "ledger-duplicate", "missing-ledger", "missing-extraction", "proof-bytes", "proof-missing", "extra-proof", "count", "policy", "invalid-gzip"])
def test_load_refuses_changed_retained_evidence(frozen: tuple[Path, dict[str, Json]],
                                              tmp_path: Path, damage: str) -> None:
    """Rebinding outer hashes cannot excuse malformed versions, escaping references or missing causes."""
    directory, manifest = frozen
    extraction = directory / manifest["extraction"]["path"]
    binding = manifest["fidelityLedger"]
    ledger_path = directory / binding["path"]
    if damage == "extraction-bytes": extraction.write_bytes(extraction.read_bytes() + b"changed")
    elif damage == "extraction-uncompressed": manifest["extraction"]["uncompressedSha256"] = "0" * 64
    elif damage == "extraction-path": manifest["extraction"]["path"] = "../manifest.json"
    elif damage == "extraction-count": manifest["extraction"]["recordedCases"] = True
    elif damage == "ledger-bytes": ledger_path.write_bytes(ledger_path.read_bytes() + b"changed")
    elif damage == "ledger-uncompressed": binding["uncompressedSha256"] = "0" * 64
    elif damage == "ledger-symlink":
        external = tmp_path / "outside.gz"
        external.write_bytes(ledger_path.read_bytes())
        ledger_path.unlink()
        ledger_path.symlink_to(external)
    elif damage in {"ledger-version", "ledger-extraction", "ledger-reference", "ledger-duplicate"}:
        ledger = json.loads(gzip.decompress(ledger_path.read_bytes()))
        if damage == "ledger-version": ledger["ledgerVersion"] = True
        elif damage == "ledger-extraction": ledger["extractionSha256"] = "0" * 64
        elif damage == "ledger-reference": ledger["entries"][0]["evidence"][0]["path"] = "../proof.txt"
        else: ledger["entries"].append(ledger["entries"][0])
        payload = serialized(ledger)
        compressed = gzip.compress(payload, mtime=0)
        ledger_path.write_bytes(compressed)
        binding.update(sha256=digest(compressed), uncompressedSha256=digest(payload))
    elif damage == "missing-ledger": del manifest["fidelityLedger"]
    elif damage == "missing-extraction": del manifest["extraction"]
    elif damage == "proof-bytes": (directory / "fidelity/proof.txt").write_text("changed")
    elif damage == "proof-missing": (directory / "fidelity/proof.txt").unlink()
    elif damage == "extra-proof": binding["evidence"]["../proof.txt"] = "0" * 64
    elif damage == "count": binding["mismatches"] = True
    elif damage == "policy": manifest["expressionSamplingPolicy"]["algorithm"] = "changed"
    elif damage == "invalid-gzip":
        ledger_path.write_bytes(b"not gzip")
        binding["sha256"] = digest(b"not gzip")
    (directory / "manifest.json").write_bytes(serialized(manifest))
    with pytest.raises(ValueError): load(directory)
