"""Both engine profiles use default DQS while frontend ambiguity fails closed."""

from pathlib import Path
import pytest
from conformance.native_connection import Connection, library_path, load_library
from belay.sqlite.errors import SqlError
from belay.sqlite.sql_tree import parse
from belay.sqlite.admission import admit
from belay.sqlite.translate import starting_schema, statements

pytestmark = [pytest.mark.integration, pytest.mark.conformance,
              pytest.mark.requires_native("sqlite3", "sqlite3-3.46.0", "sqlite-parser", "sqlite-parser-3.46.0")]


@pytest.mark.parametrize("version,suffix", [("3.51.0", ""), ("3.46.0", "-3.46.0")])
def test_library_default_and_frontend(version: str, suffix: str, runtime_root: Path, tmp_path: Path) -> None:
    """Native fallback works; quoted real identifiers remain admitted and unknown keys reject."""
    connection = Connection(load_library(library_path("sqlite3" + suffix), version), tmp_path / "dqs.db")
    parser = runtime_root / ("build/sqlite-parser" + suffix)
    schema_sql = 'CREATE TABLE "t"("id" INTEGER NOT NULL,"value" TEXT,UNIQUE("id"));'
    try:
        assert connection.configure(1013, -1) == connection.configure(1014, -1) == 1
        connection.execute_script(schema_sql)
        connection.query('INSERT INTO t VALUES(1,"fallback");')
        assert connection.query('SELECT "value" FROM "t";') == [((3, b"fallback"),)]
        connection.query('CREATE TABLE checks(x CHECK(x != "forbidden"));')
        connection.query('CREATE INDEX i ON t("nosuch");')
        assert connection.query("PRAGMA index_xinfo(i);")[0][1] == (1, -2)
        with pytest.raises(SqlError) as caught:
            starting_schema(parse(parser, (schema_sql + 'CREATE INDEX i ON t("nosuch");').encode(), "index.sql", version))
        assert caught.value.status == "UNSUPPORTED"
        indexed = starting_schema(parse(parser, (schema_sql + 'CREATE INDEX i ON t("id");').encode(), "index.sql", version))
        assert indexed[0].indexes[0].columns == ("id",)
        schema = starting_schema(parse(parser, schema_sql.encode(), "schema.sql", version))
        good = statements(parse(parser, b'UPDATE "t" SET "value"=\'ok\' WHERE "id"=1;', "good.sql", version))
        admit(schema, good)
        for sql in ('INSERT INTO t(id,value) VALUES(2,"fallback");',
                    'UPDATE t SET value="fallback" WHERE id=1;',
                    'UPDATE t SET value=\'ok\' WHERE "absent"=1;',
                    'CREATE INDEX i ON t("nosuch");'):
            with pytest.raises(SqlError) as caught:
                admit(schema, statements(parse(parser, sql.encode(), "bad.sql", version)))
            assert caught.value.status == "UNSUPPORTED"
    finally:
        connection.close()
