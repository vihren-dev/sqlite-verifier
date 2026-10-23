"""The authorizer of supplementary probes (`conformance.native_probe.select_probe`) lets a probe
read the table-valued pragmas `pragma_table_info` and `pragma_foreign_key_list`, which the
recorder probes for the ties of an `ORDER BY` (`conformance.native_ordering.query_groups`), and
still refuses the other pragmas."""

from pathlib import Path

import pytest

from conformance.native_connection import Connection, library_path, load_library

pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.requires_native("sqlite3")]


def test_probe_reads_schema_pragmas_and_refuses_others(tmp_path: Path) -> None:
    """A probe over `pragma_table_info` and `pragma_foreign_key_list` gives SQLite's rows; a
    probe over `pragma_index_list` fails as a probe that is not a read-only SELECT."""
    connection = Connection(load_library(library_path()), tmp_path / "probe.db")
    try:
        connection.query("CREATE TABLE c(a, x REFERENCES p);")
        result = connection.query_result(
            "SELECT i.name, f.\"table\" FROM pragma_table_info('c') AS i "
            "LEFT JOIN pragma_foreign_key_list('c') AS f ON f.\"from\" = i.name ORDER BY i.name;", (), readonly=True)
        assert result.rows == [((3, b"a"), (5, None)), ((3, b"x"), (3, b"p"))]
        with pytest.raises(ValueError, match="read-only SELECT"):
            connection.query_result("SELECT * FROM pragma_index_list('c');", (), readonly=True)
    finally:
        connection.close()
