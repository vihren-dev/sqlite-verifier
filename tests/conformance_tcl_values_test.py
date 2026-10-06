"""REAL/BLOB fidelity compares exact values through the actual pinned Tcl result contract."""

from copy import deepcopy
import os
from pathlib import Path
import shutil
import struct

import pytest

from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.upstream_fidelity import check_results, tcl_values
from conformance.upstream_pilot import pilot
from conformance.upstream_result_values import values_agree

pytestmark = [pytest.mark.conformance]


def real(number: float) -> Json:
    """Represent native REAL bits without replacing them with a Tcl display string."""
    return {"real": {"bits": str(int.from_bytes(struct.pack(">d", number), "big"))}}


@pytest.mark.unit
@pytest.mark.parametrize("number,text", [(123.5, "123.5"), (1e16, "10000000000000000.0"),
    (1e-30, "1e-30"), (-0.0, "-0.0"), (float("inf"), "Inf"), (float("-inf"), "-Inf"),
    (1.0000000000000002, "1.0000000000000002")])
def test_round_trip_tcl_reals(number: float, text: str) -> None:
    """Tcl decimal/exponent choices do not change a single independently recorded bit."""
    rows = [[real(number)]]
    original = deepcopy(rows)
    assert values_agree(rows, [text], "eval", 0)
    assert rows == original


@pytest.mark.unit
@pytest.mark.parametrize("number,text", [(1.0, "1.0000001"), (-0.0, "0.0"),
    (1.0, "1"), (1.0, "NaN"), (1.0, "1_0.0"), (float("inf"), "1e999"), (0.0, "1e-999")])
def test_changed_real_values_are_not_equivalent(number: float, text: str) -> None:
    """Changed bits, signed zero and text outside Tcl's default double forms are refused."""
    assert not values_agree([[real(number)]], [text], "eval", 0)


@pytest.mark.unit
@pytest.mark.parametrize("precision", [None, -1, 18, True])
def test_real_precision_requires_valid_observation(precision: int | None) -> None:
    """Historical unobserved or invalid Tcl formatting cannot establish exact equality."""
    with pytest.raises(ValueError, match="lacks valid precision"):
        values_agree([[real(1.0000001)]], ["1.0"], "eval", precision)


@pytest.mark.unit
def test_blob_bytes_and_helper_boundaries() -> None:
    """Bytearray display maps every byte directly to its codepoint, including NUL/high bytes."""
    data = bytes(range(256))
    row: Json = [{"blob": {"bytes": list(data)}}]
    assert values_agree([row], [data.decode("latin-1")], "eval", None)
    assert not values_agree([row], [data[:-1].decode("latin-1") + "x"], "eval", None)
    assert values_agree([[real(1e16), real(99.0)]], ["10000000000000000.0"], "onecolumn", 0)
    assert values_agree([[real(1.0)]], ["1"], "exists", None)
    assert values_agree([[real(1.0)]], [], "eval-script", None)
    assert values_agree([], [""], "onecolumn", None)


@pytest.mark.unit
@pytest.mark.parametrize("marker", ["", "NULL", "null", "N"])
def test_observed_null_marker_preserves_typed_values_and_helpers(marker: str) -> None:
    """Display only actual SQL NULL; empty onecolumn, exists and callback results stay distinct."""
    rows: list[Json] = [["null", {"text": {"bytes": list(b"NULL")}}]]
    original = deepcopy(rows)
    assert values_agree(rows, [marker, "NULL"], "eval", 0, marker)
    assert not values_agree(rows, [marker, "changed"], "eval", 0, marker)
    assert values_agree(rows, [marker], "onecolumn", 0, marker)
    assert values_agree([], [""], "onecolumn", 0, marker)
    assert values_agree(rows, ["1"], "exists", 0, None)
    assert values_agree(rows, [], "eval-script", 0, None)
    with pytest.raises(ValueError, match="requires captured nullvalue"):
        values_agree(rows, [marker, "NULL"], "eval", 0, None)
    assert rows == original


@pytest.mark.integration
@pytest.mark.requires_native("sqlite3")
def test_pinned_tcl_real_blob_acquisition_and_negative_results(tmp_path: Path) -> None:
    """Real SQL recovers CAST and binary values, while changed results and precision fail."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl result fidelity")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    shutil.copyfile(Path(__file__).with_name("upstream_value_calls.test"), upstream / "test/values.test")
    output = tmp_path / "captured"
    report = pilot(Path(fixture), upstream, output, None, ("values.test",), tcl_precision=0)
    assert report["tclDisplayPrecisionPolicy"]["requested"] == 0
    assert report["files"][0]["tclDisplayPrecision"] == {"original": 15, "established": 0, "requested": 0}
    instances = {row["id"]: row for row in report["files"][0]["instances"]}
    accepted = {"values-cast", "values-prefix", "values-real-edges", "values-blob", "values-onecolumn",
                "values-null-NULL", "values-null-null", "values-null-N", "values-null-prefix",
                "values-null-helpers", "values-null-reset"}
    assert {name for name, row in instances.items() if row["result"] == "recorded"} == accepted, instances
    assert "upstream Tcl expectation failed" in instances["values-original-expectation"]["result"]
    assert "results differ from Tcl execution" in instances["values-rounded"]["result"]
    assert "precision" in instances["values-traced"]["result"]
    assert "Tcl NULL display marker unobservable" in instances["values-null-unobserved"]["result"]
    assert report["files"][0]["runtimeComplete"] is True
    _, records = load(output)
    native_replay(records)
    for record in records:
        expected = record["upstream"]["id"]
        assert expected in accepted
        observed = record["upstream"]["tclNullvalueEvidence"]
        assert observed == instances[expected]["tclNullvalueEvidence"]
        assert observed["successfulCalls"] == record["upstream"]["tclResultPrecision"]["successfulCalls"]
        assert None not in observed["values"]
        if expected.startswith("values-null-"):
            assert any(cell == "null" for event in record["trace"] for row in event["rows"] for cell in row)
            if expected == "values-null-prefix":
                assert observed == {"values": ["N", "NULL"], "successfulCalls": 2}
            elif expected == "values-null-reset":
                assert observed == {"values": [""], "successfulCalls": 1}
            continue
        precision = {"values": [0], "successfulCalls": 2 if expected == "values-prefix" else 1}
        assert record["upstream"]["tclResultPrecision"] == precision
        assert instances[expected]["tclResultPrecision"] == precision
        original = deepcopy(record)
        # Validate this exact projection before changing only the external observations.
        commands = [record["migrationSql"]]
        helper = "onecolumn" if expected == "values-onecolumn" else "eval"
        rows = [row for event in record["trace"] for row in event["rows"]]
        candidate = {"prefixCodes": [], "prefixResults": [], "commands": commands,
            "helpers": [helper], "codes": [0],
            "results": [tcl_values(rows, helper, precision=0)], "precisions": [0]}
        candidate["prefixCodes"] = record["setupOutcomes"]
        candidate["prefixResults"] = [tcl_values(rows, precision=0) for rows in record["setupResults"]]
        candidate["prefixPrecisions"] = [0] * len(record["setupOutcomes"])
        check_results(record, candidate)
        candidate["results"][0][0] = "materially changed"
        with pytest.raises(ValueError):
            check_results(record, candidate)
        assert record == original
