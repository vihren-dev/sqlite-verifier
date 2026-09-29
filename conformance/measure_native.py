"""Execute admitted structural fixtures against a separately gcov-instrumented SQLite."""

import argparse
import json
from pathlib import Path

from conformance.model_check import compiled_many
from conformance.native_replay import decode_cell
from conformance.native_trace import Fixture, record


def main() -> None:
    """GCOV_PREFIX belongs to this child process; profiling writes on normal process exit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", type=Path)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    args = parser.parse_args()
    cases = [json.loads(line) for line in args.cases.read_text().splitlines()]
    assert all(result["verdict"] == "AGREE" for result in compiled_many(cases, args.runtime_root.resolve()))
    actual = []
    for case in cases:
        rows = {name: [(row["rowid"], tuple(decode_cell(cell) for cell in row["values"]))
                      for row in table["rows"]] for name, table in case["initial"]}
        fixture = Fixture(case["schemaSql"], case["migrationSql"], rows, "coverage")
        observed = record(fixture, args.runtime_root.resolve() / "build/sqlite-parser", args.library.resolve())
        assert observed["nativeTrace"] == case["nativeTrace"]
        actual.append(observed)
    assert all(result["verdict"] == "AGREE" for result in compiled_many(actual, args.runtime_root.resolve()))
    print(json.dumps({"agreedInstrumentedCases": len(actual)}))


if __name__ == "__main__":
    main()
