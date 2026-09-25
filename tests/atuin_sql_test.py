"""Bounded native old-data preservation check of the supplied application SQL."""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"conformance"))
from atuin_sql_check import run


if __name__ == "__main__":
    report = run(os.environ.get("SQLITE346", "sqlite3-3.46.0"))
    rendered = json.dumps(report, indent=2) + "\n"
    (ROOT/"build").mkdir(exist_ok=True)
    (ROOT/"build/atuin-sql.json").write_text(rendered)
    print(rendered, end="")
