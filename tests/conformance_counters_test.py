"""The counters of a native record of version 7 (ADR 0024, D1) in the subject's readers.

A record of version 7 holds the counters of the writer connection just before the migration runs.
`conformance.predict.mapped` and `conformance.native_replay.model_case` give them to the model, and
the model's run starts from them. The records here are written by hand from a version 5 record
whose migration reads the three counters: only the version and the `counters` field differ, and the
hand-written counters are the values that the native record shows for the same reads.
"""

import json
from pathlib import Path
import subprocess
import sys

import pytest

from conformance.model_check import compiled, prove
from conformance.native_replay import model_case
from conformance.record_counters import COUNTER_KEYS, counters_input, counters_wire
from conformance.sql_text import runtime_translator
from judge.records import subject_input
from tests.conformance_predict_test import profiled

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("translation-program", "sqlite3")]

SETUP = "CREATE TABLE t(a INTEGER); INSERT INTO t VALUES (7), (8);"
READ = "SELECT changes(), total_changes(), last_insert_rowid();"
COUNTERS = {"changes": 2, "totalChanges": 2, "lastInsertRowid": 2}
"""The counters after `SETUP`: two rows inserted, the last with rowid 2."""
NATIVE_ROW = [[{"integer": {"value": 2}}, {"integer": {"value": 2}}, {"integer": {"value": 2}}]]
"""The native rows of `READ` after `SETUP`, as the record holds them."""
PREDICT_TIMEOUT_SECONDS = 60
"""One predict run over a few small cases."""


def counted_record(runtime_root: Path, version: int, **more: object) -> dict[str, object]:
    """A record of the given version of `READ` after `SETUP`: the events of a version 5 record, whose
    one event shows the native values of the three counters, with the hand-written fields."""
    record = profiled(runtime_root, "counted", SETUP, READ)
    assert record["nativeVersion"] == 5 and len(record["trace"]) == 1
    assert record["trace"][0]["rows"] == NATIVE_ROW
    return {**record, "nativeVersion": version, **more}


def predict(runtime_root: Path, *records: dict[str, object]) -> list[dict[str, object]]:
    """Run the predict command over the hand-written inputs of the records: the subject input of
    the judge, with the record's counters when it has them."""
    lines = "".join(json.dumps({**subject_input(record), **({"counters": record["counters"]}
                                                         if "counters" in record else {})}) + "\n"
                    for record in records)
    result = subprocess.run([sys.executable, "-m", "conformance.predict", "--runtime", str(runtime_root)],
                            input=lines, capture_output=True, text=True, timeout=PREDICT_TIMEOUT_SECONDS, check=False)
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines()]


def test_version_7_input_starts_from_the_counters(runtime_root: Path) -> None:
    """`conformance.predict.mapped` and `VerifierConformance.Predict.predictRun`: the input of a
    version 7 record is predicted from its counters, so the reads of the three counters give the
    values of the record. The same input as version 6 has unknown counters: the model's run ends at
    the first read, and the case is out of the model's scope. A counter that differs from the
    record's changes the predicted output."""
    version_6 = counted_record(runtime_root, 6)
    version_7 = counted_record(runtime_root, 7, counters=COUNTERS)
    other = {**version_7, "name": "other", "counters": {**COUNTERS, "changes": 5}}
    unknown, known, shifted = predict(runtime_root, version_6, version_7, other)
    assert unknown["status"] == "predicted" and not unknown["supported"], unknown
    assert known["status"] == "predicted" and known["supported"], known
    assert known["outputs"][0]["rows"] == NATIVE_ROW, known["outputs"]
    assert shifted["supported"] and shifted["outputs"][0]["rows"][0][0] != known["outputs"][0]["rows"][0][0], shifted


def test_version_7_case_starts_from_the_counters(runtime_root: Path, tmp_path: Path) -> None:
    """`conformance.native_replay.model_case` and `VerifierConformance.Classify.classifyRunCase`: a
    version 7 record gives a case with the record's counters; the compiled classifier and a kernel
    proof agree with it. The same record as version 6 has no counters, and the model does not
    support the case. A changed counter disagrees with the native output."""
    translator = runtime_translator(runtime_root)
    case = model_case(counted_record(runtime_root, 7, counters=COUNTERS), translator)
    assert case["continues"] is True and case["counters"] == COUNTERS
    answer = compiled(case, runtime_root, emit_lean=True)
    assert answer["verdict"] == "AGREE", answer
    prove(answer["caseLean"], runtime_root, tmp_path / "Counted.lean", case=case)
    older = model_case(counted_record(runtime_root, 6), translator)
    assert "counters" not in older and compiled(older, runtime_root)["verdict"] == "MODEL_UNSUPPORTED"
    shifted = model_case(counted_record(runtime_root, 7, counters={**COUNTERS, "totalChanges": 9}), translator)
    assert compiled(shifted, runtime_root)["verdict"] == "DISAGREE"


def test_counters_are_checked_before_the_model_sees_them() -> None:
    """`conformance.record_counters.counters_wire`: a version 7 record without the counters, with a
    key missing or added, with a value that is not an integer, a negative count or a value outside 64
    bits is corrupt evidence; a record of another version must not hold the field; and a version
    without counters gives no field to the model."""
    good = {"nativeVersion": 7, "counters": COUNTERS}
    assert counters_wire(good) == COUNTERS and counters_input(good) == {"counters": COUNTERS}
    assert counters_input({"nativeVersion": 6}) == {} and counters_wire({"nativeVersion": 6}) is None
    assert counters_wire({"nativeVersion": 7, "counters": {**COUNTERS, "lastInsertRowid": -(2 ** 63)}}) is not None
    bad = [None, {}, {**COUNTERS, "extra": 0}, {k: COUNTERS[k] for k in COUNTER_KEYS[:2]},
           {**COUNTERS, "changes": -1}, {**COUNTERS, "changes": True}, {**COUNTERS, "changes": 1.0},
           {**COUNTERS, "totalChanges": 2 ** 63}, {**COUNTERS, "lastInsertRowid": 2 ** 63},
           {**COUNTERS, "lastInsertRowid": -(2 ** 63) - 1}]
    for counters in bad:
        with pytest.raises(ValueError, match="counter"):
            counters_wire({"nativeVersion": 7, "counters": counters})
    with pytest.raises(ValueError, match="only version 7 holds counters"):
        counters_wire({"nativeVersion": 6, "counters": COUNTERS})
