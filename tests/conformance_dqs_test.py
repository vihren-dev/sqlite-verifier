"""Both engine profiles use default DQS; resolution applies the double-quoted-string fallback.

The frontend keeps whether a name was written in double quotes
(`belay.sqlite.syntax_expressions.identifier`); Lean resolution applies SQLite's
fallback under the profile's DQS settings. Native SQLite is the oracle here.
"""

from pathlib import Path

import pytest

from belay.sqlite.sql_tree import parse
from belay.sqlite.syntax import statements
from conformance.model_check import compiled
from conformance.native_connection import Connection, library_path, load_library
from conformance.native_trace import Fixture, record
from conformance.record_parser import default_parser
from tests.runtime_fixtures import profile_parser

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite3-3.46.0", "parser-library")]
SCHEMA = 'CREATE TABLE "t"("id" INTEGER NOT NULL,"value" TEXT,UNIQUE("id"));'


@pytest.mark.parametrize("version,suffix", [("3.51.0", ""), ("3.46.0", "-3.46.0")])
def test_library_default_and_frontend(version: str, suffix: str, runtime_root: Path, tmp_path: Path) -> None:
    """The library keeps default DQS, and the mapping records a double-quoted name for resolution."""
    library = load_library(library_path("sqlite3" + suffix), version)
    assert not library.sqlite3_compileoption_used(b"DQS=0")
    connection = Connection(library, tmp_path / "dqs.db")
    try:
        assert connection.configure(1013, -1) == connection.configure(1014, -1) == 1
    finally:
        connection.close()
    mapped = statements(parse(profile_parser(runtime_root, version), b'INSERT INTO t(id,value) VALUES(2,"fallback");',
                              "dqs.sql"))
    assert mapped[0].value == {"insert": {"table": "t", "columns": ["id", "value"], "rows": [
        [{"numeric": {"text": "2"}}, {"identifier": {"name": "fallback", "doubleQuoted": True}}]], "conflicts": [], "algorithm": None}}


@pytest.mark.parametrize("migration", [
    'INSERT INTO t(id,value) VALUES(2,"fallback");',
    'INSERT INTO t(id,value) VALUES(2,\'ok\'); UPDATE t SET value="fallback" WHERE "id"=2;',
    'UPDATE t SET value=\'ok\' WHERE absent=1;',
], ids=["insert_fallback", "update_fallback", "unknown_filter_name"])
def test_double_quoted_names_agree_with_sqlite(runtime_root: Path, migration: str) -> None:
    """Resolution's fallback and its `no such column` error agree with the pinned native engine."""
    case = record(Fixture(SCHEMA, migration, {}, "dqs"), default_parser(runtime_root))
    assert compiled(case, runtime_root)["verdict"] == "AGREE", case["provenance"]
