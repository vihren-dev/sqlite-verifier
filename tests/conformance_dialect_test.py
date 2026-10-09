"""Conformance replay refuses to parse a case whose recorded profile has no built dialect.

These tests check `conformance/record_parser.py` and its use in `conformance/corpus.py`
and `conformance/native_replay.py`.
"""

from pathlib import Path

import pytest

from conformance.execution_profile import measured_profile
from conformance.native_connection import Connection, library_path, load_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "parser-library")]


def test_profile_without_a_built_dialect_is_counted_apart(tmp_path: Path, runtime_root: Path) -> None:
    """`corpus.replay` gives a case whose recorded build has no dialect in the parser library
    the verdict MODEL_UNSUPPORTED with its own reason and count, and never parses it."""
    from conformance.corpus import replay
    from conformance.native_record import record_sql
    from conformance.record_parser import NO_PARSER_REASON
    connection = Connection(load_library(library_path()), tmp_path / "other-build.db")
    try:
        profile = measured_profile(connection, name="other-build")
    finally:
        connection.close()
    record = record_sql("", "SELECT 1;", name="other-build", outputs=True, profile=profile)
    other = "2000-01-01 00:00:00 " + "0" * 64
    record = {**record, "sourceId": other, "profile": {**record["profile"], "sourceId": other}}
    result = replay([record], runtime_root)
    assert result["counts"] == {"MODEL_UNSUPPORTED": 1} and result["noParserForDialect"] == 1
    [case] = result["cases"]
    assert case["reason"] == NO_PARSER_REASON and "another build" in case["error"]
