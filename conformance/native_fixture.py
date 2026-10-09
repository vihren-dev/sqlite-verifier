"""Replay preserved fixture SQL in one pinned native connection, retaining all observations."""

import json
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from belay.sqlite.errors import SqlError
from belay.sqlite.sql_tree import SqlParser, parse
from conformance.record_parser import default_parser
from import_fixture import fixture

SOURCE_ID = "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b"


def arrays(text: str) -> list[list[dict[str, object]]]:
    """Decode successive native JSON result sets without flattening their typed observations."""
    decoder = json.JSONDecoder()
    remaining = text.strip()
    results: list[list[dict[str, object]]] = []
    while remaining:
        result, end = decoder.raw_decode(remaining)
        if not isinstance(result, list) or not all(isinstance(row, dict) for row in result):
            raise ValueError("Native engine did not return row objects")
        results.append(result)
        remaining = remaining[end:].strip()
    return results


def flat_tcl(results: list[list[dict[str, object]]]) -> list[str]:
    """Preserve SQLite Tcl execsql's flat row order and empty representation of NULL."""
    flat: list[str] = []
    for result in results:
        for row in result:
            for value in row.values():
                if value is not None and not isinstance(value, int):
                    raise ValueError("Imported assertion only supports integer and NULL cells")
                flat.append("" if value is None else str(value))
    return flat


def run(native: str, parser: SqlParser, selected: int | None = None, *, final_only: bool = False) -> dict[str, object]:
    """Check native observations independently of the still-unwired formal model."""
    imported = fixture()
    if final_only and selected is not None:
        raise ValueError("Select either one upstream case or final observations")
    setup = imported["prerequisite_setup"]
    cases = imported["cases"]
    if selected is not None:
        if selected < 0 or selected >= len(cases):
            raise ValueError("Unknown upstream occurrence")
        cases = cases[:selected + 1]
    commands = [item["shell"] for item in imported["connection_setup"]]
    # The shell enables defensive mode; the upstream Tcl connection uses C-API defaults.
    commands.extend([".dbconfig trusted_schema on", ".dbconfig defensive off", ".dbconfig dqs_dml on", ".dbconfig dqs_ddl on", ".limit column 2000"])
    commands.extend(item["sql"] for item in setup)
    with TemporaryDirectory() as directory:
        folder = Path(directory)
        for index, case in enumerate(cases):
            if not final_only and (selected is None or index == selected):
                try:
                    parse(parser, case["sql"].encode(), f"upstream-case-{index}.sql")
                except SqlError as error:
                    raise ValueError(f"Production parser rejected upstream fixture SQL: {error}") from error
            commands.extend([f".print CASE_{index}", case["sql"]])
        if selected is None:
            commands.extend([".print OBSERVATIONS", "SELECT rowid,a,b,c FROM t1 ORDER BY rowid;",
                "PRAGMA schema_version;", "SELECT type,name,sql FROM sqlite_schema ORDER BY name;"])
        commands.extend([
            ".print ENGINE", "SELECT sqlite_version() AS version,sqlite_source_id() AS source;",
            "PRAGMA compile_options;",
        ])
        result = subprocess.run([native, "-init", "/dev/null", "-batch", "-bail", "-json",
                                 str(folder / "fixture.db")],
                                input="\n".join(commands) + "\n", capture_output=True,
                                text=True, timeout=5, check=True)
    sections: dict[str, list[str]] = {}
    current = "CONFIGURATION"
    for line in result.stdout.splitlines():
        if line in [*(f"CASE_{i}" for i in range(len(cases))), "OBSERVATIONS", "ENGINE"]:
            current = line
        else:
            sections.setdefault(current, []).append(line)
    engine = arrays("\n".join(sections["ENGINE"]))
    if engine[0] != [{"version": "3.51.0", "source": SOURCE_ID}]:
        raise ValueError("Native engine version/source does not match the pinned profile")
    options = [row["compile_options"] for row in engine[1]]
    configuration = [line.split() for line in sections["CONFIGURATION"]]
    if ("MAX_COLUMN=2000" not in options or ["dqs_dml", "on"] not in configuration
            or ["dqs_ddl", "on"] not in configuration):
        raise ValueError("Native engine compile settings do not match the declared profile")
    comparisons: list[dict[str, object]] = []
    for index, case in enumerate(cases):
        if final_only or (selected is not None and index != selected):
            continue
        observed = arrays("\n".join(sections.get(f"CASE_{index}", [])))
        if flat_tcl(observed) != case["expected_flat"]:
            raise AssertionError((case["upstream_id"], case["occurrence"], observed, case["expected_tcl"]))
        comparisons.append({"upstream_id": case["upstream_id"], "occurrence": case["occurrence"],
                            "expected_tcl": case["expected_tcl"], "native_rows": observed})
    return {"profile": "3.51.0", "coverage": imported["coverage"], "cases": comparisons,
            "final_observations": arrays("\n".join(sections.get("OBSERVATIONS", []))),
            "source_id": SOURCE_ID, "compile_options": options}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: native_fixture.py SQLITE3 RUNTIME_ROOT")
    print(json.dumps(run(sys.argv[1], default_parser(Path(sys.argv[2]))), indent=2))
