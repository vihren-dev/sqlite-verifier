"""Source-owned precision retains exact native REAL values and refuses rounded collisions."""

from copy import deepcopy
import os
from pathlib import Path
import shutil
import struct

import pytest

from conformance.case_format import Json
from conformance.corpus import load, native_replay
from conformance.freeze_profiles import result_precision
from conformance.upstream_pilot import pilot
from conformance.upstream_result_values import values_agree

pytestmark = [pytest.mark.conformance]


def real(number: float) -> Json:
    """Use independently specified IEEE bits, preserving negative zero."""
    return {"real": {"bits": str(int.from_bytes(struct.pack(">d", number), "big"))}}


@pytest.mark.unit
@pytest.mark.parametrize("precision", [3, 6, 15, 17])
def test_observed_precision_requires_exact_value(precision: int) -> None:
    """A rounded display that fits one value must not certify its adjacent IEEE value."""
    assert values_agree([[real(1.0), real(-0.0), real(1.25)]], ["1.0", "-0.0", "1.25"], "eval", precision)
    assert not values_agree([[real(1.0000000000000002)]], ["1.0"], "eval", precision)
    assert not values_agree([[real(-0.0)]], ["0.0"], "eval", precision)


@pytest.mark.unit
def test_retained_precision_policy_preserves_historical_guarantee() -> None:
    """Only policy v2 permits observed nonzero precision; missing observations stay refused."""
    value: Json = {"values": [15], "successfulCalls": 1}
    result_precision(value, accepted=True, policy_version=2)
    with pytest.raises(ValueError, match="precision evidence differs"):
        result_precision(value, accepted=True, policy_version=1)
    for invalid in (None, 18):
        with pytest.raises(ValueError, match="precision evidence differs"):
            result_precision({"values": [invalid], "successfulCalls": 1}, accepted=True, policy_version=2)


@pytest.mark.integration
@pytest.mark.requires_native("sqlite3")
def test_pinned_source_precision_date_arithmetic_and_corruption(tmp_path: Path) -> None:
    """Real Tcl precision 15 admits exact dates and signed zero, while rounded SQL stays excluded."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned Nix upstream target for Tcl precision capture")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    (upstream / "test/date_precision.test").write_text("""
set testdir [file join $env(CONFORMANCE_UPSTREAM) test]
source [file join $testdir tester.tcl]
set ::tcl_precision 15
reset_db
do_test precision-exact {db eval {SELECT 1.25,-0.0,julianday('2024-02-29')}} {1.25 -0.0 2460369.5}
reset_db
do_test precision-collision {db eval {SELECT 1.0,1.0000000000000002}} {1.0 1.0}
reset_db
do_test precision-changes {
  set first [db eval {SELECT 1.25}]
  set ::tcl_precision 0
  concat $first [db eval {SELECT 1.0000000000000002}]
} {1.25 1.0000000000000002}
finish_test
""")
    output = tmp_path / "capture"
    report = pilot(Path(fixture), upstream, output, None, ("date_precision.test",), catalog_profile_policy=True)
    source = report["files"][0]
    assert source["runtimeExit"] == 0 and source["runtimeComplete"], source
    assert report["tclDisplayPrecisionPolicy"]["version"] == 2
    assert [i["result"] for i in source["instances"]] == [
        "recorded", "native acquisition: Native fidelity difference for date_precision:precision-collision:1: "
        "assertion results differ from Tcl execution. Exclude this source assertion; its recorded results differ.", "recorded"]
    _, records = load(output)
    assert records[0]["upstream"]["tclResultPrecision"]["values"] == [15]
    assert records[1]["upstream"]["tclResultPrecision"]["values"] == [0, 15]
    native_replay(records)
    corrupted = deepcopy(records[0])
    bits = corrupted["trace"][0]["rows"][0][0]["real"]
    bits["bits"] = str(int(bits["bits"]) ^ 1)
    with pytest.raises(ValueError, match="Native replay changed|results differ from Tcl execution"):
        native_replay([corrupted])
