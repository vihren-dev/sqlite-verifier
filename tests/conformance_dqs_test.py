"""Both engine profiles use default DQS while frontend ambiguity fails closed."""

from pathlib import Path
import pytest
from conformance.native_connection import Connection, library_path, load_library
from belay.sqlite.errors import SqlError
from belay.sqlite.sql_tree import parse
from belay.sqlite.admission import admit
from belay.sqlite.translate import starting_schema, statements
from tests.runtime_fixtures import profile_parser

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite3-3.46.0", "parser-library")]


@pytest.mark.parametrize("version,suffix", [("3.51.0", ""), ("3.46.0", "-3.46.0")])
def test_library_default_and_frontend(version: str, suffix: str, runtime_root: Path, tmp_path: Path) -> None:
    """The library keeps default DQS; quoted real identifiers remain admitted and unknown keys reject."""
    library = load_library(library_path("sqlite3" + suffix), version)
    assert not library.sqlite3_compileoption_used(b"DQS=0")
    connection = Connection(library, tmp_path / "dqs.db")
    parser = profile_parser(runtime_root, version)
    schema_sql = 'CREATE TABLE "t"("id" INTEGER NOT NULL,"value" TEXT,UNIQUE("id"));'
    try:
        assert connection.configure(1013, -1) == connection.configure(1014, -1) == 1
        with pytest.raises(SqlError) as caught:
            starting_schema(parse(parser, (schema_sql + 'CREATE INDEX i ON t("nosuch");').encode(), "index.sql"))
        assert caught.value.status == "UNSUPPORTED"
        indexed = starting_schema(parse(parser, (schema_sql + 'CREATE INDEX i ON t("id");').encode(), "index.sql"))
        assert indexed[0].indexes[0].columns == ("id",)
        schema = starting_schema(parse(parser, schema_sql.encode(), "schema.sql"))
        good = statements(parse(parser, b'UPDATE "t" SET "value"=\'ok\' WHERE "id"=1;', "good.sql"))
        admit(schema, good)
        for sql in ('INSERT INTO t(id,value) VALUES(2,"fallback");',
                    'UPDATE t SET value="fallback" WHERE id=1;',
                    'UPDATE t SET value=\'ok\' WHERE "absent"=1;',
                    'CREATE INDEX i ON t("nosuch");'):
            with pytest.raises(SqlError) as caught:
                admit(schema, statements(parse(parser, sql.encode(), "bad.sql")))
            assert caught.value.status == "UNSUPPORTED"
    finally:
        connection.close()
