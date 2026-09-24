"""Extract one explicitly bounded upstream Tcl fixture slice without rewriting SQL."""

import hashlib
import json
import re
from pathlib import Path
from schema import Case, Fixture

ROOT = Path(__file__).resolve().parent


def upstream_text() -> str:
    """Require the reviewed upstream bytes before applying the bounded extractor."""
    path = ROOT / "upstream" / "alter3.test"
    hashes: dict[str, str] = json.loads((ROOT / "upstream" / "sha256.json").read_text())
    if hashlib.sha256(path.read_bytes()).hexdigest() != hashes[path.name]:
        raise ValueError("The pinned alter3.test changed")
    return path.read_text()


def execsql_case(source: str, start: int, name: str, occurrence: int) -> Case:
    """Import only the literal single-execsql shape used by the selected three calls."""
    pattern = rf"do_test {re.escape(name)} \{{\s*execsql \{{(.*?)\n  \}}\s*\}} \{{([^\n]*)\}}\n"
    match = re.match(pattern, source[start:], flags=re.S)
    if match is None:
        raise ValueError(f"Selected upstream assertion shape changed: {name}")
    expected = match.group(2)
    if re.sub(r"\{\}|-?\d+|\s+", "", expected):
        raise ValueError("Selected Tcl expectation is outside the literal integer/empty subset")
    return {
        "upstream_id": name, "occurrence": occurrence,
        "source_start_line": source.count("\n", 0, start) + 1,
        "source_end_line": source.count("\n", 0, start + match.end() - 1) + 1,
        "sql": match.group(1), "expected_tcl": expected,
        "expected_flat": ["" if token == "{}" else token
                          for token in re.findall(r"\{\}|-?\d+", expected)],
    }


def setup_sql(source: str, name: str, operation: str) -> str:
    """Retain the prerequisite SQL from the named earlier upstream assertion."""
    start = source.index(f"do_test {name} {{")
    match = re.search(rf"\b{operation} \{{(.*?)\n[ \t]*\}}", source[start:], flags=re.S)
    if match is None:
        raise ValueError(f"Missing upstream prerequisite: {name}")
    return match.group(1)


def fixture() -> Fixture:
    """Return ordered call instances, including the duplicate alter3-3.1 identifier."""
    source = upstream_text()
    assertions = re.findall(r"^\s*do_(?:test|execsql_test|catchsql_test)\s+(\S+)", source, re.M)
    first = source.index("do_test alter3-3.1 {")
    second = source.index("do_test alter3-3.1 {", first + 1)
    third = source.index("do_test alter3-3.2 {", second)
    return {
        "source": "sqlite-src-3510000/test/alter3.test",
        "profile": "3.51.0",
        "coverage": {"selected_call_instances": 3, "selected_distinct_ids": 2,
                     "upstream_textual_call_sites": len(assertions),
                     "upstream_distinct_textual_ids": len(set(assertions))},
        "connection_setup": [{"upstream": "sqlite3_db_config db LEGACY_FILE_FORMAT 1",
                              "shell": ".dbconfig legacy_file_format on"}],
        "prerequisite_setup": [
            {"upstream_id": name, "sql": setup_sql(source, name, operation)}
            for name, operation in [("alter3-2.1", "execsql"), ("alter3-2.4", "catchsql"),
                                    ("alter3-2.5", "execsql"), ("alter3-2.99", "execsql")]
        ],
        "cases": [execsql_case(source, first, "alter3-3.1", 1),
                  execsql_case(source, second, "alter3-3.1", 2),
                  execsql_case(source, third, "alter3-3.2", 1)],
        "model_status": "NOT_YET_MODEL_CHECKED",
    }


if __name__ == "__main__":
    print(json.dumps(fixture(), indent=2))
