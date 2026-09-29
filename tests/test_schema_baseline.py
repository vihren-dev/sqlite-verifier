"""Protect an optional associated schema without restricting reusable contracts."""

import json
from pathlib import Path

import pytest

from migration_check.baseline import check_baseline
from migration_check.diagnostics import Rejection

pytestmark = [pytest.mark.unit, pytest.mark.approval]
APPROVED = {"approved/Requirements.lean": "a" * 64, "approved/Interpretation.lean": "b" * 64}


def test_optional_schema_pin(tmp_path: Path) -> None:
    """Only explicitly pinned schema hashes join the mandatory approved closure."""
    baseline = tmp_path / "baseline.json"
    baseline.write_text(json.dumps(APPROVED))
    check_baseline(baseline, {**APPROVED, "schema.sql": "c" * 64})
    pinned = {**APPROVED, "schema.sql": "c" * 64}
    baseline.write_text(json.dumps(pinned))
    check_baseline(baseline, pinned)
    for actual in (APPROVED, {**APPROVED, "schema.sql": "d" * 64}):
        with pytest.raises(Rejection, match="schema.sql"):
            check_baseline(baseline, actual)
    baseline.write_text(json.dumps({**APPROVED, "schema.sql": "bad"}))
    with pytest.raises(Rejection, match="Invalid approved baseline hash"):
        check_baseline(baseline, pinned)
