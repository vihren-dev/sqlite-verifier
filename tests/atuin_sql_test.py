"""Independent native old-data preservation checks of the source-backed application SQL."""

import json
import os
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from atuin_sql_check import CASES, run

pytestmark = [pytest.mark.integration, pytest.mark.atuin, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3-3.46.0")]


@pytest.mark.parametrize("case", CASES)
def test_native_history(case: str, runtime_root: Path, case_artifacts: Path) -> None:
    """One independently seeded history preserves exact old stored classes/bytes and integrity."""
    report = run(os.environ.get("SQLITE346", "sqlite3-3.46.0"), (case,), runtime_root)
    assert len(report) == 1 and report[0]["case"] == case
    case_artifacts.mkdir(parents=True, exist_ok=True)
    (case_artifacts / "native-history.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    report = run(os.environ.get("SQLITE346", "sqlite3-3.46.0"))
    rendered = json.dumps(report, indent=2) + "\n"
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build/atuin-sql.json").write_text(rendered)
    print(rendered, end="")
