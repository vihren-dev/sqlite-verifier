"""The real Tcl observer preserves binder inputs and refuses unobservable source values."""

from copy import deepcopy
import hashlib
import os
from pathlib import Path
import shutil
import subprocess

import pytest

from conformance.upstream_assertions import assertions
from conformance.upstream_bindings import recorded_calls
from conformance.corpus import load, native_replay
from conformance.native_storage import serialized
from conformance.upstream_pilot import pilot

pytestmark = [pytest.mark.conformance, pytest.mark.integration, pytest.mark.requires_native("sqlite3")]

SOURCE = Path(__file__).with_name("upstream_binding_calls.test").read_text()


def test_observer_keeps_source_storage_bytes_and_scope(tmp_path: Path) -> None:
    """Observe unchanged real Tcl execution, including numeric text, BLOBs, NUL and caller locals."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned upstream target for Tcl binding observation")
    source = tmp_path / "bindings.test"
    source.write_text(SOURCE)
    proxy = Path(__file__).resolve().parents[1] / "conformance/upstream_proxy.tcl"
    runs: list[subprocess.CompletedProcess[str]] = []
    events = tmp_path / "events.tsv"
    for index, arguments in enumerate(([fixture, str(source)], [fixture, str(proxy)])):
        directory = tmp_path / str(index)
        directory.mkdir()
        runs.append(subprocess.run(arguments, cwd=directory, capture_output=True, text=True,
            timeout=15, env={**os.environ, "CONFORMANCE_TEST": str(source),
                "CONFORMANCE_EVENTS": str(events), "CONFORMANCE_TCL_PRECISION": "0"}))
    assert all(run.returncode == 0 for run in runs), [(run.stdout, run.stderr) for run in runs]
    assert all("OBSERVER-READS=1" in run.stdout for run in runs)
    assert all("OBSERVER-CALLBACKS=1" in run.stdout for run in runs)
    assert all("OBSERVER-OBJECT-STABLE=1" in run.stdout for run in runs)
    candidates = {case["id"]: case for case in assertions(events.read_text())}
    types = candidates["bindings-types"]
    assert not types["failed"] and not types["implicitBindingReasons"], types
    observed = types["bindingObservations"][0]
    assert observed["values"] == {
        "$::i": {"integer": {"value": 42}}, "$::r": {"real": {"bits": "4607182418800017409"}},
        "$::negative": {"real": {"bits": "9223372036854775808"}},
        "$::text": {"text": {"bytes": [52, 50]}}, "$::blob": {"blob": {"bytes": [0, 128, 255]}},
        "$::nul": {"text": {"bytes": [192, 128]}}, "$::utf": {"text": {"bytes": [226, 130, 172]}},
        "$::cesu": {"text": {"bytes": [237, 160, 189, 237, 184, 128]}}}
    assert observed["objects"]["$::blob"] == {"type": "bytearray", "hasString": False}
    assert observed["objects"]["$::r"] == {"type": "double", "hasString": False}
    string_blob = recorded_calls(candidates["bindings-blob-string"])["assertion"][0]
    assert string_blob["bindings"] == {"$::blob": {"text": {"bytes": [192, 128, 194, 128, 195, 191]}}}
    assert string_blob["objects"]["$::blob"] == {"type": "bytearray", "hasString": True}
    repeat = recorded_calls(candidates["bindings-repeat"])["assertion"][0]
    changed = recorded_calls(candidates["bindings-changed"])["assertion"][0]
    assert repeat["bindings"] == {"$::value": {"integer": {"value": 7}}}
    assert changed["bindings"] == {"$::value": {"integer": {"value": 8}}}
    assert not candidates["bindings-quoted"]["implicitBindingReasons"]
    assert recorded_calls(candidates["bindings-quoted"])["assertion"][0]["bindings"] == {}
    assert recorded_calls(candidates["bindings-local"])["assertion"][0]["bindings"] == {
        "$local": {"integer": {"value": 11}}}
    assert recorded_calls(candidates["bindings-forced"])["assertion"][0]["bindings"] == {
        "@::forced": {"blob": {"bytes": [172]}}}
    forced = recorded_calls(candidates["bindings-forced-number"])["assertion"][0]
    after_forced = recorded_calls(candidates["bindings-after-forced-number"])["assertion"][0]
    assert forced["bindings"] == {"@::forced_number": {"blob": {"bytes": [49, 46, 50, 53]}}}
    assert forced["objects"]["@::forced_number"] == {"type": "double", "hasString": False}
    assert after_forced["bindings"] == {"$::forced_number": {"text": {"bytes": [49, 46, 50, 53]}}}
    for name, reason in (("missing", "missing Tcl parameter variable: $::absent"),
                         ("traced", "traced Tcl parameter variable: $::traced"),
                         ("mixed", "mixed Tcl parameter conversion: ::mixed"),
                         ("row-script", "Tcl parameter row script context: $::row_value"),
                         ("array", "unsupported Tcl parameter variable form: $::array(key)"),
                         ("callback", "Tcl parameter execution callback context: $::callback_value")):
        case = candidates["bindings-" + name]
        assert not case["failed"] and reason in case["implicitBindingReasons"], case
        with pytest.raises(ValueError, match="call evidence is incomplete"):
            recorded_calls(case)


def test_actual_capture_retains_setup_calls_and_detects_parameter_corruption(tmp_path: Path) -> None:
    """Pinned Tcl and fresh SQLite agree on original calls, setup parameters and changing object types."""
    fixture = shutil.which("testfixture")
    if fixture is None or "CONFORMANCE_UPSTREAM" not in os.environ:
        pytest.skip("Run the pinned upstream target for source-bound Tcl acquisition")
    upstream = tmp_path / "upstream"
    (upstream / "test").mkdir(parents=True)
    (upstream / "test/bindings.test").write_text(SOURCE)
    output = tmp_path / "capture"
    report = pilot(Path(fixture), upstream, output, None, ("bindings.test",), tcl_precision=0)
    file = report["files"][0]
    assert file["runtimeExit"] == 0 and file["runtimeComplete"], file
    assert report["corpusVersion"] == 2 and report["tclBindingPolicy"]["version"] == 1
    _manifest, records = load(output)
    native_replay(records)
    by_id = {record["upstream"]["id"]: record for record in records}
    assert {"bindings-types", "bindings-blob-string", "bindings-setup", "bindings-repeat",
            "bindings-changed", "bindings-local", "bindings-forced", "bindings-forced-number",
            "bindings-after-forced-number"} <= by_id.keys(), file["instances"]
    instances = {instance["id"]: instance for instance in file["instances"]}
    for name in ("nul-display", "cesu-display"):
        assert "Tcl TEXT display encoding is not reproduced" in instances["bindings-" + name]["result"]
    for name in ("nul-sql", "cesu-sql"):
        assert "Tcl SQL encoding is not reproduced" in instances["bindings-" + name]["exclusions"]
        assert "bindings-" + name not in by_id
    for record in records:
        assert hashlib.sha256(serialized(record["sourceCalls"])).hexdigest() == instances[
            record["upstream"]["id"]]["tclCallsSha256"] == record["upstream"]["tclCallsSha256"]
    setup = by_id["bindings-setup"]
    assert any(event["parameterNames"] == ["$::value"] and event["parameters"] == [
        {"integer": {"value": 7}}] for events in setup["setupBindings"] for event in events)
    changed = by_id["bindings-changed"]
    assert changed["trace"][0]["parameterNames"] == ["$::value"]
    assert changed["trace"][0]["parameters"] == [{"integer": {"value": 8}}]
    corrupted = deepcopy(changed)
    corrupted["sourceCalls"]["assertion"][0]["bindings"]["$::value"] = {"integer": {"value": 9}}
    corrupted["trace"][0]["parameters"] = [{"integer": {"value": 9}}]
    with pytest.raises(ValueError, match="differ|changed"):
        native_replay([corrupted])
