"""The model case of a native record of version 6 (`conformance.native_replay.model_case`).

A recorder of version 6 runs on after an SQL error, so its trace has one event for each
statement, also after a failed one. `model_case` accepts such a trace only for version 6 and
marks the case as one whose run continues; `VerifierConformance.Classify.classifyCase` then
compares it with the model's run that continues (`runPassFrom`). The record here is written by
hand from two version 5 records: a prepare error in autocommit changes nothing, so the event of
a later statement is the one of a record without the failed statement.
"""

from copy import deepcopy
from pathlib import Path

import pytest

from conformance.case_format import Json
from conformance.model_check import compiled, prove
from conformance.native_replay import model_case
from conformance.sql_text import runtime_translator
from tests.conformance_predict_test import profiled

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean, pytest.mark.requires_native("translation-program", "sqlite3")]

SETUP = "CREATE TABLE t(a INTEGER);"
FIRST = "INSERT INTO t VALUES (1);"
FAILED = " INSERT INTO missing VALUES (2);"
LATER = " SELECT a FROM t;"


def continuing_record(runtime_root: Path) -> dict[str, Json]:
    """A version 6 record of `FIRST`, `FAILED` and `LATER`: the events of a version 5 record of
    the first two, which stops at the prepare error, and the event of `LATER` from a version 5
    record of `FIRST` and `LATER`."""
    stopped = profiled(runtime_root, "stopped", SETUP, FIRST + FAILED)
    later = profiled(runtime_root, "later", SETUP, FIRST + LATER)
    assert [event["phase"] for event in stopped["trace"]] == [None, "prepare"]
    assert [event["sql"] for event in later["trace"]] == [FIRST, LATER]
    return {**stopped, "name": "continuing", "nativeVersion": 6, "migrationSql": FIRST + FAILED + LATER,
            "trace": [*stopped["trace"], later["trace"][1]]}


def test_version_6_case_continues_and_agrees(runtime_root: Path, tmp_path: Path) -> None:
    """A version 6 record gives a case that continues, with one observation and one output for
    each statement; the compiled classifier and a kernel proof agree with it, and a changed
    observation after the failed statement disagrees at that statement."""
    case = model_case(continuing_record(runtime_root), runtime_translator(runtime_root))
    assert case["continues"] is True and len(case["nativeTrace"]) == 4 and len(case["outputs"]) == 3
    answer = compiled(case, runtime_root, emit_lean=True)
    assert answer["verdict"] == "AGREE", answer
    prove(answer["caseLean"], runtime_root, tmp_path / "Continuing.lean", case=case)
    changed = deepcopy(case)
    changed["nativeTrace"][3]["transactionOpen"] = True
    assert compiled(changed, runtime_root) == {"verdict": "DISAGREE", "position": 2}


def test_only_version_6_has_events_after_an_error(runtime_root: Path) -> None:
    """`model_case` refuses events after an error in a record of version 5, and a version 6
    record without an event for each statement, as a statement-count mismatch."""
    record = continuing_record(runtime_root)
    translator = runtime_translator(runtime_root)
    with pytest.raises(ValueError, match="statement-count mismatch"):
        model_case({**record, "nativeVersion": 5}, translator)
    with pytest.raises(ValueError, match="statement-count mismatch"):
        model_case({**record, "trace": record["trace"][:2]}, translator)
