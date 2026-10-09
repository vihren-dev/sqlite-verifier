"""Progress partitions frozen cases while overlapping features keep their provenance scope."""

from collections import Counter
import hashlib
import importlib
import json
from pathlib import Path
import sys

import pytest

from conformance.case_format import Json
from conformance.corpus import load
from conformance.corpus_evidence import FEATURE_LABEL_VIEWS, feature_counts
from conformance.progress import RUNTIME_FILES, VERDICTS, progress

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.unit, pytest.mark.conformance]


@pytest.fixture
def inputs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path, Path]:
    """Supply distinct case verdicts independently of raw requirement aliases and sorted names."""
    corpus, runtime = tmp_path / "corpus", tmp_path / "runtime"
    requirements = tmp_path / "requirements.json"
    inventory = {"count": 2, "requirements": [
        {"id": "R-11111-22222-33333", "file": "lang.html", "publicTclEvidence": []},
        {"id": "R-44444-55555-66666", "file": "unused.html", "publicTclEvidence": []}]}
    requirements.write_text(json.dumps(inventory))
    records: list[dict[str, Json]] = [
        {"name": "z-first", "part": "boundary-interaction", "features": ["shared", "a", "a"],
         "requirements": ["R-11111-22222", "R-11111-22222-33333"]},
        {"name": "y-second", "part": "boundary-interaction", "features": ["shared"], "requirements": []},
        {"name": "b-third", "part": "upstream", "features": ["shared", "upstream"],
         "featureMetadataScope": "source-file", "upstream": {"file": "z.test"}, "requirements": []},
        {"name": "a-fourth", "part": "upstream", "features": ["upstream"],
         "featureMetadataScope": "source-file", "upstream": {"file": "z.test"}, "requirements": []}]
    manifest: dict[str, Json] = {"corpusVersion": 4, "casesSha256": "loaded-and-bound",
        "executionProfiles": [{"name": "declared-profile"}],
        "extraction": {"sha256": "validated-extraction"},
        "fidelityLedger": {"sha256": "validated-ledger", "evidence": {"proof.gz": "proof-hash"}},
        "shards": [{"path": "shards/0000.gz", "source": "authored", "part": "boundary-interaction",
                    "recordedCases": 2, "casesSha256": "first-shard"},
                   {"path": "shards/0001.gz", "source": "z.test", "part": "upstream",
                    "recordedCases": 2, "casesSha256": "second-shard"}]}
    for path in [corpus / "manifest.json", *(corpus / shard["path"] for shard in manifest["shards"]),
                 *(runtime / relative for relative in RUNTIME_FILES)]:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(manifest) if path.name == "manifest.json" else path.name)

    def loaded(directory: Path) -> tuple[dict[str, Json], list[dict[str, Json]]]:
        """Treat fixture declarations as already validated by the shared loader."""
        assert directory == corpus
        return manifest, records

    def replayed(cases: list[dict[str, Json]], selected_runtime: Path) -> dict[str, Json]:
        """Keep all verdict categories visible without using a native or model oracle."""
        assert cases == records and selected_runtime == runtime
        return {"counts": {verdict: 1 for verdict in VERDICTS}, "byRequirement": {"raw-alias": {"AGREE": 2}},
                "cases": [{"name": record["name"], "verdict": verdict}
                          for record, verdict in zip(records, VERDICTS, strict=True)]}

    monkeypatch.setattr("conformance.progress.load", loaded)
    monkeypatch.setattr("conformance.progress.replay", replayed)
    return corpus, requirements, runtime


def test_part_feature_shard_denominators(inputs: tuple[Path, Path, Path]) -> None:
    """File membership never adds case-feature credit; duplicate scenario labels count once."""
    report = progress(*inputs)
    assert report["denominator"] == sum(row["denominator"] for row in report["byPart"].values()) == 4
    assert report["byPart"]["boundary-interaction"]["counts"] == dict(zip(VERDICTS, (1, 1, 0, 0), strict=True))
    assert [row["source"] for row in report["byShard"]] == ["authored", "z.test"]
    assert [row["index"] for row in report["byShard"]] == [0, 1]
    assert sum(row["denominator"] for row in report["byShard"]) == 4
    assert report["byShard"][1]["counts"] == dict(zip(VERDICTS, (0, 0, 1, 1), strict=True))
    assert {key: row["denominator"] for key, row in report["byCaseFeatureLabel"].items()} == {"a": 1, "shared": 2}
    assert {key: row["denominator"] for key, row in report["bySourceFileLabel"].items()} == {"shared": 1, "upstream": 2}
    assert report["byUnscopedFeatureLabel"] == {} and "byFeature" not in report
    assert report["byRequirement"] == {"raw-alias": {"AGREE": 2}}
    assert [row["counts"]["AGREE"] for row in report["requirementMatrix"]] == [1, 0]


def test_historical_upstream_labels_cannot_become_case_coverage(inputs: tuple[Path, Path, Path]) -> None:
    """Missing historical scope stays unknown even when the same label annotates authored cases."""
    module = importlib.import_module("conformance.progress")
    _manifest, records = module.load(inputs[0])
    del records[2]["featureMetadataScope"]
    report = progress(*inputs)
    assert report["byCaseFeatureLabel"]["shared"]["denominator"] == 2
    assert report["byUnscopedFeatureLabel"]["shared"]["counts"]["MODEL_UNSUPPORTED"] == 1
    assert "shared" not in report["bySourceFileLabel"]
    assert report["bySourceFileLabel"]["upstream"]["counts"]["HARNESS_ERROR"] == 1


def test_report_binds_runtime_profiles_shards_evidence(inputs: tuple[Path, Path, Path]) -> None:
    """The report names actual binaries and transport bytes alongside validated evidence declarations."""
    corpus, requirements, runtime = inputs
    report = progress(*inputs)
    manifest = json.loads((corpus / "manifest.json").read_text())
    assert report["runtimeSha256"] == {relative: hashlib.sha256((runtime / relative).read_bytes()).hexdigest()
                                      for relative in RUNTIME_FILES}
    assert report["corpusManifestSha256"] == hashlib.sha256((corpus / "manifest.json").read_bytes()).hexdigest()
    assert report["executionProfiles"] == manifest["executionProfiles"]
    assert report["corpusEvidence"] == {key: manifest[key] for key in ("extraction", "fidelityLedger")}
    assert [row["sha256"] for row in report["byShard"]] == [
        hashlib.sha256((corpus / row["path"]).read_bytes()).hexdigest() for row in manifest["shards"]]
    assert {"model_check.py", "execution_profile.py", "corpus_evidence.py"} <= report["harnessSha256"].keys()
    assert "belay/sqlite/sql_model.py" in report["frontendSha256"]
    (runtime / RUNTIME_FILES[1]).write_bytes(b"changed runner")
    assert progress(*inputs)["runtimeSha256"] != report["runtimeSha256"]


@pytest.mark.parametrize("relative", RUNTIME_FILES)
def test_absent_binary_cannot_produce_progress(inputs: tuple[Path, Path, Path], relative: str) -> None:
    """Unsupported cases still require exact compiled runtime identity."""
    (inputs[2] / relative).unlink()
    with pytest.raises(FileNotFoundError):
        progress(*inputs)


def test_cli_defaults_to_frozen_v5(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """The ordinary progress command selects the final corpus without caller flags."""
    module = importlib.import_module("conformance.progress")

    def generated(corpus: Path, requirements: Path, runtime: Path) -> dict[str, Json]:
        """Observe CLI selection independently of report aggregation."""
        assert corpus == Path("conformance/corpus-v5")
        return {"denominator": 0, "counts": {}}

    monkeypatch.setattr(module, "progress", generated)
    output = tmp_path / "progress.json"
    monkeypatch.setattr(sys, "argv", ["progress", "--output", str(output)])
    module.main()
    assert json.loads(output.read_text()) == {"denominator": 0, "counts": {}}


@pytest.mark.integration
@pytest.mark.requires_lean
@pytest.mark.requires_native("parser-library")
@pytest.mark.parametrize("version", [4, 5])
def test_actual_frozen_partition_requirement_inventory_and_identities(runtime_root: Path, version: int) -> None:
    """All final cases appear once while the full inventory and native Unsupported boundary remain explicit."""
    corpus = ROOT / f"conformance/corpus-v{version}"
    manifest, records = load(corpus)
    report = progress(corpus, ROOT / "conformance/requirements-3.51.0.json", runtime_root)
    assert report["denominator"] == manifest["recordedCases"] == len(records)
    assert report["corpusVersion"] == version
    assert [case["name"] for case in report["cases"]] == [record["name"] for record in records]
    assert report["counts"] == dict(Counter(case["verdict"] for case in report["cases"]))
    assert not {"DISAGREE", "HARNESS_ERROR"} & report["counts"].keys()
    assert {key: row["denominator"] for key, row in report["byPart"].items()} == manifest["byPart"]
    combined: dict[str, int] = {}
    for view in FEATURE_LABEL_VIEWS:
        for label, row in report[view].items():
            combined[label] = combined.get(label, 0) + row["denominator"]
    if version == 4:
        assert report["counts"] == {"MODEL_UNSUPPORTED": 1264}
        assert len(records) == 1264 and combined == manifest["byFeature"]
        assert report["bySourceFileLabel"]["json_each"]["denominator"] == 219
        assert report["byCaseFeatureLabel"]["json_each"]["denominator"] == 1
        assert sum(bool(sum(row["counts"].values())) for row in report["requirementMatrix"]) == 110
    else:
        expected_labels = feature_counts(records)
        assert {view: {label: row["denominator"] for label, row in report[view].items()}
                for view in FEATURE_LABEL_VIEWS} == expected_labels
        assert all(manifest[view] == expected_labels[view] for view in FEATURE_LABEL_VIEWS)
    assert "byFeature" not in report
    assert [row["path"] for row in report["byShard"]] == [row["path"] for row in manifest["shards"]]
    assert sum(row["denominator"] for row in report["byShard"]) == len(records)
    assert report["requirementMatrixRows"] == report["requirementInventoryCount"] == 3500
    assert report["executionProfiles"] == manifest["executionProfiles"]
    assert report["corpusEvidence"]["fidelityLedger"] == manifest["fidelityLedger"]
    assert len(report["runtimeSha256"]) == 2
