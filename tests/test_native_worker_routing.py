"""The development CLI and report forward actual native storage and path auditing to spawned workers."""

from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

import pytest

from conformance import replay_tiers
from conformance.case_format import Json
from conformance.execution_profile import ExecutionProfile
from conformance.native_storage import serialized
from tests.test_native_workers import clock_cases

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "parser-library")]


def test_cli_and_report_forward_real_storage_and_fixture_paths(
        clock_cases: tuple[ExecutionProfile, list[dict[str, Json]]], tmp_path: Path,
        runtime_root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Four real native cases expose dropped CLI storage or report audit arguments without a frozen timing run."""
    _profile, cases = clock_cases
    generic, synthetic = tmp_path / "generic", tmp_path / "synthetic"
    records = [{**deepcopy(case), "part": "boundary-interaction"} for case in cases[:2]]
    synthetic_records = [{**deepcopy(case), "name": f"synthetic-{index}", "part": "synthetic"}
                         for index, case in enumerate(cases[2:])]
    manifest: dict[str, Json] = {"corpusVersion": 5, "recordedCases": 2,
        "casesSha256": hashlib.sha256(serialized(records)).hexdigest(),
        "executionProfiles": [cases[0]["profile"]]}
    synthetic_manifest: dict[str, Json] = {**manifest, "corpusVersion": 4, "recordedCases": 2,
        "casesSha256": hashlib.sha256(serialized(synthetic_records)).hexdigest()}
    for directory, value in ((generic, manifest), (synthetic / "corpus", synthetic_manifest)):
        directory.mkdir(parents=True)
        (directory / "manifest.json").write_bytes(serialized(value))

    def load_fixture(directory: Path) -> tuple[dict[str, Json], list[dict[str, Json]]]:
        """Use a tiny acquired catalog to isolate routing from the unchanged full frozen-loading boundary."""
        assert directory == generic
        return manifest, records

    def bound_fixture(source: Path, corpus: Path) -> tuple[dict[str, Json], list[dict[str, Json]]]:
        """Retain two real synthetic records while isolating the unchanged workload-binding boundary."""
        assert source == synthetic and corpus == synthetic / "corpus"
        return synthetic_manifest, synthetic_records

    paths: list[Path] = []
    report = replay_tiers.report

    def audited_report(generic: Path, synthetic: Path, runtime: Path, *,
                       temporary_root: Path | None = None) -> dict[str, Json]:
        """Supply only the optional path list while exercising the actual report and CLI storage argument."""
        return report(generic, synthetic, runtime, temporary_root=temporary_root, fixture_paths=paths)

    storage, output = tmp_path / "selected files", tmp_path / "report.json"
    storage.mkdir()
    monkeypatch.setattr(replay_tiers, "AUTHORED_COUNTS_BY_VERSION", {5: 2})
    monkeypatch.setattr(replay_tiers, "load_development_corpus", load_fixture)
    monkeypatch.setattr(replay_tiers, "bound_records", bound_fixture)
    monkeypatch.setattr(replay_tiers, "report", audited_report)
    monkeypatch.setattr(sys, "argv", ["replay_tiers", "--corpus", str(generic), "--synthetic", str(synthetic),
        "--runtime-root", str(runtime_root), "--temporary-root", str(storage), "--output", str(output)])
    replay_tiers.main()
    result = json.loads(output.read_text())
    assert result["selectedDenominator"] == 4 and result["counts"] == {"MODEL_UNSUPPORTED": 4}
    assert len(paths) == 4 and len(set(paths)) == 4
    assert all(path.is_relative_to(storage) and path.name == "case.db" and not path.exists() for path in paths)
    assert list(storage.iterdir()) == []
