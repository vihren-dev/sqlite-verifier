"""The fixed source catalog and real generated Tcl cases retain deterministic C6 membership."""

from copy import deepcopy
import hashlib
import os
from pathlib import Path
import shutil

import pytest

from conformance.corpus import load, native_replay
from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_storage import serialized
from conformance.upstream_catalog import catalog_patterns, file_exclusion_reasons, source_catalog
from conformance.upstream_pilot import pilot
from conformance.upstream_sampling import EXPRESSION_COHORTS, sampling_policy, select_candidates
from conformance.upstream_selection import candidate_reasons

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_fixed_catalog_and_explicit_file_exclusions() -> None:
    """Exactly 55 reviewed sources include 18 exclusions without excluding ordinary BLOB SQL."""
    catalog = source_catalog()
    assert len(catalog) == len(set(catalog_patterns())) == 55
    assert sum(bool(source["fileExclusions"]) for source in catalog) == 18
    assert {source["file"] for source in catalog if "json_extract" in source["features"]} == {"json101.test"}
    for file, reason in (("alterfault.test", "fault injection"), ("altermalloc.test", "allocation fault injection"),
        ("altercorrupt.test", "database corruption"), ("alterauth.test", "authorizer context"),
        ("e_wal.test", "WAL context"), ("e_uri.test", "URI context"),
        ("e_blobopen.test", "incremental BLOB-handle operations"), ("e_fts3.test", "FTS context")):
        assert reason in file_exclusion_reasons(file)
    assert file_exclusion_reasons("walfault.test") == ["WAL context", "fault injection"]
    assert file_exclusion_reasons("blob.test") == file_exclusion_reasons("rowallock.test") == []
    assert len(sampling_policy(EXPRESSION_COHORTS)["cohorts"]) == 57


def test_identity_sampling_ignores_native_acceptance() -> None:
    """Hash ranking is reproducible when refusal flags change, and preserves all other reasons."""
    candidates = [{"id": f"generated-{i}", "exclusions": [], "failed": False,
                   "commands": ["SELECT 1;"], "codes": [0]} for i in range(12)]
    cohorts = (("loops.test", "generated-", 4),)
    rejected, report = select_candidates("loops.test", candidates, cohorts)
    expected = sorted((hashlib.sha256(serialized(["loops.test", candidate["id"], i])).hexdigest(), i)
                      for i, candidate in enumerate(candidates))[:4]
    assert [(item["sha256"], item["occurrence"]) for item in report[0]["selected"]] == expected
    changed = deepcopy(candidates)
    for candidate in changed:
        candidate.update(exclusions=["multiple connections"], failed=True)
    assert select_candidates("loops.test", changed, cohorts) == (rejected, report)
    index = next(iter(rejected))
    assert set(candidate_reasons(changed[index], selected=500, limit=None,
        sampling_reason=rejected[index])) == {"multiple connections", "upstream Tcl expectation failed",
                                             "expression prefix sampling: generated-"}
    assert candidate_reasons(candidates[0], selected=500, limit=None) == []
    duplicate_ids = [{**candidate, "id": "generated-same"} for candidate in candidates]
    assert len(select_candidates("loops.test", duplicate_ids, cohorts)[0]) == 8
    for invalid in ((("loops.test", "", 4),), (("loops.test", "generated-", 0),),
                    (("loops.test", "generated-", 1), ("loops.test", "generated-1", 1))):
        with pytest.raises(ValueError, match="sampling cohort"):
            sampling_policy(invalid)


def test_real_uncapped_capture_and_prefix_sampling(tmp_path: Path) -> None:
    """More than 20 cases record; sampled callback cases keep refusals and never refill a cohort."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl capture")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_sampling_calls.test"), upstream / "test/loops.test")
    for excluded in ("wal.test", "e_blobopen.test", "alterfault.test"):
        (upstream / "test" / excluded).write_text("error {excluded file must not execute}\n")
    connection = Connection(load_library(library_path()), tmp_path / "measure.db")
    try:
        profile = measured_profile(connection, name="sampled-native")
    finally:
        connection.close()
    cohorts = (("loops.test", "generated-", 4), ("loops.test", "blocked-", 4))
    first = pilot(Path(fixture), upstream, tmp_path / "first", None, ("*.test",), profile=profile, sampling=cohorts)
    repeated = pilot(Path(fixture), upstream, tmp_path / "repeated", None, ("*.test",), profile=profile, sampling=cohorts)
    assert first["perFileLimit"] is None and first["recordedCases"] == 29
    assert first["expressionSamplingPolicy"] == sampling_policy(cohorts)
    source = next(file for file in first["files"] if file["file"] == "loops.test")
    again = next(file for file in repeated["files"] if file["file"] == "loops.test")
    assert source["runtimeExit"] == 0 and source["runtimeAssertions"] == 49
    assert source["expressionSampling"] == again["expressionSampling"]
    assert source["instances"] == again["instances"]
    for excluded in first["files"]:
        if excluded["file"] != "loops.test":
            assert excluded["fileExclusions"] and "runtimeExit" not in excluded
    choices = {cohort["prefix"]: {item["occurrence"] for item in cohort["selected"]}
               for cohort in source["expressionSampling"]}
    for instance in source["instances"]:
        if instance["id"].startswith("blocked-"):
            expected = {"application callback: function"}
            if instance["occurrence"] not in choices["blocked-"]:
                expected.add("expression prefix sampling: blocked-")
            assert set(instance["exclusions"]) == expected
    _, records = load(tmp_path / "first")
    assert len(records) == 29 and all(record["nativeVersion"] == 4 for record in records)
    native_replay(records, profile=profile)
    uncapped = pilot(Path(fixture), upstream, tmp_path / "uncapped", None, ("loops.test",), profile=profile)
    assert uncapped["recordedCases"] == 37
