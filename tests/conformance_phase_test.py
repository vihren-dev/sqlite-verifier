"""The error phase of case version 5 (ADR 0008, "How `resolve` is tested").

`conformance.native_trace.record` records whether each native error came from
`sqlite3_prepare_v2` or from `sqlite3_step`, and `VerifierConformance.Case`
requires a resolution prepare error to be a prepare error and every other modeled
error to be a step error. A case with a changed phase therefore disagrees.
"""

from copy import deepcopy
from pathlib import Path

import pytest

from conformance.model_check import compiled
from conformance.native_trace import Fixture, record
from conformance.record_parser import default_parser

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "parser-library")]
SCHEMA = "CREATE TABLE t(id INTEGER NOT NULL, UNIQUE(id));"
ROWS = {"t": [(1, ((1, 1),))]}
"""One stored row, so that inserting its key again violates the UNIQUE constraint."""


@pytest.mark.parametrize("migration,phase,other", [
    ("INSERT INTO missing VALUES(1);", "prepare", "step"),
    ("INSERT INTO t(id) VALUES(1);", "step", "prepare"),
], ids=["prepare_error", "step_error"])
def test_recorded_phase_must_match_the_model(runtime_root: Path, migration: str, phase: str, other: str) -> None:
    """The recorded phase agrees with the model's phase, and the other phase disagrees."""
    case = record(Fixture(SCHEMA, migration, ROWS, "phase"), default_parser(runtime_root))
    assert case["version"] == 5 and case["nativeTrace"][-1]["phase"] == phase
    assert all(observation["phase"] is None for observation in case["nativeTrace"][:-1])
    assert compiled(case, runtime_root)["verdict"] == "AGREE", case["provenance"]
    changed = deepcopy(case)
    changed["nativeTrace"][-1]["phase"] = other
    assert compiled(changed, runtime_root)["verdict"] == "DISAGREE"
    unobserved = deepcopy(case)
    unobserved["nativeTrace"][-1]["phase"] = None
    assert compiled(unobserved, runtime_root)["verdict"] == "AGREE"


def test_phase_without_an_error_is_a_harness_error(runtime_root: Path) -> None:
    """`VerifierConformance.Json.decodeCase` refuses a phase on a successful observation and names it."""
    case = record(Fixture(SCHEMA, "INSERT INTO t(id) VALUES(2);", ROWS, "phase"), default_parser(runtime_root))
    case["nativeTrace"][1]["phase"] = "step"
    result = compiled(case, runtime_root)
    assert result["verdict"] == "HARNESS_ERROR" and "native observation 1" in result["error"], result
