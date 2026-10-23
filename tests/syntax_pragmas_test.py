"""The mapping of the pragmas of the model to Syntax JSON (`pragma` in
`packages/belay-sqlite-text/Belay/Sqlite/Translation/Schema.lean`, through the text package's program).

ADR 0018, D4 and ADR 0019, D2: the translation maps the query forms of `PRAGMA foreign_keys` and
`PRAGMA recursive_triggers` and each value that SQLite's `sqlite3GetBoolean` reads as on or off,
the table name of
`PRAGMA table_info` and `PRAGMA foreign_key_list`, the optional table name of
`PRAGMA foreign_key_check`, and the row limit or table name of
`PRAGMA integrity_check` and `PRAGMA quick_check`. It refuses every other pragma, a schema name
and any other value, which the model does not describe.
"""

from collections.abc import Callable

import pytest

from belay.sqlite.errors import SqlError
from conformance.sql_text import Translation

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_native]


def mapped(parse_sql: Callable[..., Translation], sql: str) -> list[object]:
    """Return the syntax JSON of every statement of the SQL."""
    return [item.value for item in parse_sql(sql).statements()]


def pragma(form: dict[str, object]) -> dict[str, object]:
    """Return the syntax JSON of a pragma statement with the form."""
    return {"pragma": {"pragma": form}}


def test_foreign_keys_pragma_keeps_its_value(parse_sql: Callable[..., Translation]) -> None:
    """`pragma` maps the query form to no value and each boolean form to its value, with the
    name and the words in either ASCII case and quoted words dequoted."""
    sql = ("PRAGMA foreign_keys; PRAGMA foreign_keys = ON; PRAGMA FOREIGN_KEYS = off; PRAGMA foreign_keys(1); "
           "PRAGMA foreign_keys = 0; PRAGMA foreign_keys = 'Yes'; PRAGMA foreign_keys = no; PRAGMA foreign_keys = TRUE; "
           "PRAGMA \"foreign_keys\" = false;")
    assert mapped(parse_sql, sql) == [pragma({"setting": {"setting": "foreignKeys", "value": value}})
                                      for value in (None, True, False, True, False, True, False, True, False)]


def test_recursive_triggers_pragma_keeps_its_value(parse_sql: Callable[..., Translation]) -> None:
    """`pragma` maps the query form of `recursive_triggers` to no value and each boolean form to
    its value, as for `foreign_keys`, with the name in either ASCII case."""
    sql = "PRAGMA recursive_triggers; PRAGMA RECURSIVE_TRIGGERS = on; PRAGMA recursive_triggers(0); PRAGMA recursive_triggers = 'yes';"
    assert mapped(parse_sql, sql) == [pragma({"setting": {"setting": "recursiveTriggers", "value": value}})
                                      for value in (None, True, False, True)]


def test_schema_pragmas_keep_the_table_name(parse_sql: Callable[..., Translation]) -> None:
    """`pragma` maps `table_info` and `foreign_key_list` with the table name in parentheses or
    after `=`, as a name or a string, without its quotes, and the pragma name in any case."""
    sql = ("PRAGMA table_info(t); PRAGMA TABLE_INFO = 'My T'; PRAGMA table_info(\"x\"\"y\"); "
           "PRAGMA foreign_key_list(c); PRAGMA Foreign_Key_List = [c];")
    assert mapped(parse_sql, sql) == [
        pragma({"tableInfo": {"table": "t"}}), pragma({"tableInfo": {"table": "My T"}}),
        pragma({"tableInfo": {"table": "x\"y"}}), pragma({"foreignKeyList": {"table": "c"}}),
        pragma({"foreignKeyList": {"table": "c"}})]


def test_foreign_key_check_keeps_the_optional_table_name(parse_sql: Callable[..., Translation]) -> None:
    """`pragma` maps `foreign_key_check` alone to no table, and with a name or a string in
    parentheses or after `=` to the table name without its quotes, with the pragma name in any case."""
    sql = "PRAGMA foreign_key_check; PRAGMA FOREIGN_KEY_CHECK(c); PRAGMA foreign_key_check = 'My C'; PRAGMA foreign_key_check(\"1\");"
    assert mapped(parse_sql, sql) == [pragma({"foreignKeyCheck": {"table": table}}) for table in (None, "c", "My C", "1")]


def check(quick: bool, limit: int, table: str | None) -> dict[str, object]:
    """Return the syntax JSON of a check pragma."""
    return pragma({"check": {"quick": quick, "limit": limit, "table": table}})


def test_check_pragmas_keep_the_limit_or_the_table(parse_sql: Callable[..., Translation]) -> None:
    """`pragma` maps `integrity_check` and `quick_check` alone to the limit 0, an unsigned or signed
    decimal integer to its value without the sign, as `sqlite3GetInt32` reads it, and a name or a
    string, also of digits, to a table name."""
    sql = ("PRAGMA integrity_check; PRAGMA QUICK_CHECK; PRAGMA integrity_check(2); PRAGMA integrity_check(-2); "
           "PRAGMA quick_check(+1); PRAGMA integrity_check = 1; PRAGMA integrity_check(0); "
           "PRAGMA integrity_check(2147483647); PRAGMA integrity_check('1'); PRAGMA quick_check(\"My T\");")
    assert mapped(parse_sql, sql) == [
        check(False, 0, None), check(True, 0, None), check(False, 2, None), check(False, 2, None),
        check(True, 1, None), check(False, 1, None), check(False, 0, None), check(False, 2147483647, None),
        check(False, 0, "1"), check(True, 0, "My T")]


@pytest.mark.parametrize("value", ["1.5", "0x2", "2147483648", "-2147483648", "ON", "DELETE", "DEFAULT"])
def test_other_check_values_are_refused(parse_sql: Callable[..., Translation], value: str) -> None:
    """`pragma` refuses a real, a hex integer, an integer above 2147483647 and the words `ON`,
    `DELETE` and `DEFAULT` as the value of a check pragma, which SQLite reads in other ways."""
    with pytest.raises(SqlError) as raised:
        parse_sql(f"PRAGMA integrity_check({value});").statements()
    assert raised.value.status == "UNSUPPORTED"
    assert "Only a decimal row limit up to 2147483647 or a table name" in str(raised.value)


@pytest.mark.parametrize(("sql", "message"), [
    ("PRAGMA journal_mode;",
     "Only PRAGMA foreign_keys, recursive_triggers, table_info, foreign_key_list, foreign_key_check, integrity_check and "
     "quick_check are modeled"),
    ("PRAGMA main.foreign_keys = ON;", "without a schema name"),
    ("PRAGMA main.table_info(t);", "without a schema name"),
    ("PRAGMA foreign_keys = 2;", "Only on, off, yes, no, true, false, 0 and 1"),
    ("PRAGMA foreign_keys = -1;", "Only on, off, yes, no, true, false, 0 and 1"),
    ("PRAGMA foreign_keys = full;", "Only on, off, yes, no, true, false, 0 and 1"),
    ("PRAGMA recursive_triggers = 2;", "the value of PRAGMA foreign_keys and recursive_triggers"),
    ("PRAGMA main.recursive_triggers;", "without a schema name"),
    ("PRAGMA table_info;", "Write the table name in parentheses"),
    ("PRAGMA table_info(1);", "Only a table name is modeled"),
    ("PRAGMA foreign_key_list(-1);", "Only a table name is modeled"),
    ("PRAGMA table_info(ON);", "Only a table name is modeled"),
    ("PRAGMA foreign_key_check(1);", "Only a table name is modeled"),
    ("PRAGMA main.foreign_key_check;", "without a schema name"),
])
def test_other_pragmas_and_values_are_refused(parse_sql: Callable[..., Translation], sql: str, message: str) -> None:
    """`pragma` refuses another pragma, a schema name and a value that is not one of the modeled
    words, numbers or names, with its source range."""
    with pytest.raises(SqlError) as raised:
        parse_sql(sql).statements()
    assert raised.value.status == "UNSUPPORTED" and message in str(raised.value)
