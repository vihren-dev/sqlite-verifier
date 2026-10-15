"""Compare missing-field defaults read after ALTER with both pinned SQLite engines."""

import json
from pathlib import Path

import pytest

from belay.sqlite.quoted_text import quoted_string
from conformance.case_format import Json, cell_wire
from conformance.native_connection import Connection, library_path
from conformance.native_library import library_binary, load_library
from tests.column_default_value_test import CASES
from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean("compiler"),
              pytest.mark.requires_native("sqlite3", "sqlite3-3.46.0")]

READ_CASES = CASES + [
    ("1_2.5", '.numeric "1_2.5"'), ("1_2", '.numeric "1_2"'),
    ("-09223372036854775808", '.negate (.numeric "09223372036854775808")'),
    ("-1.50", '.negate (.numeric "1.50")'), ("+1.50", '.positive (.numeric "1.50")'),
    ("0.0", '.numeric "0.0"'), ("-0.0", '.negate (.numeric "0.0")'),
    ("0xFFFFFFFFFFFFFFFF", '.numeric "0xFFFFFFFFFFFFFFFF"'),
    ("-0xFFFFFFFFFFFFFFFF", '.negate (.numeric "0xFFFFFFFFFFFFFFFF")'),
    ("[true]", '.identifier "true" false'),
    ("1.50", '.numeric "1.50"'), ("1e0", '.numeric "1e0"'),
    ("9223372036854775808", '.numeric "9223372036854775808"'),
    ("-0x8000000000000000", '.negate (.numeric "0x8000000000000000")'),
    ("0x1ffffffffffffffff", '.numeric "0x1ffffffffffffffff"'),
    ("-0x1ffffffffffffffff", '.negate (.numeric "0x1ffffffffffffffff")'),
    ("+0x1ffffffffffffffff", '.positive (.numeric "0x1ffffffffffffffff")'),
]
"""Readback differs from INSERT for numeric text and overflowing hexadecimal literals."""


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
@pytest.mark.parametrize("affinity", ["INTEGER", "NUMERIC", "REAL", "TEXT", "BLOB"])
def test_added_default_readback(version: str, affinity: str, tmp_path: Path,
        lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """The default reader matches SQLite values for old rows, including affinity and numeric boundaries."""
    connection = Connection(load_library(library_path(library_binary(version)), version), tmp_path / "native.db")
    expected: list[Json] = []
    try:
        for index, (literal, _) in enumerate(READ_CASES):
            connection.execute_script(f"CREATE TABLE t{index}(id BLOB); INSERT INTO t{index} VALUES(7);"
                f"ALTER TABLE t{index} ADD COLUMN added {affinity} DEFAULT {literal};")
            expected.append(cell_wire(connection.query(f"SELECT added FROM t{index};")[0][0]))
    finally:
        connection.close()
    inputs = ", ".join(f"⟨({expression}), {quoted_string(literal)}⟩" for literal, expression in READ_CASES)
    source = f'''import Belay.Sqlite.Codec
import Belay.Sqlite.Resolution.ReadDefaults
open Belay.Sqlite Lean
#eval do
  let inputs : List Syntax.DefaultExpression := [{inputs}]
  let values := inputs.map fun written =>
    let column : CatalogColumn := {{name := "added", declaredType := some {quoted_string(affinity)},
                                   defaultValue := some written}}
    (readDefaultValue column).toOption
  IO.println (toJson values).compress
'''
    actual = json.loads(compile_checks(source, tmp_path, lean_sysroot, lean_libraries))
    assert actual == expected, {"literals": [literal for literal, _ in READ_CASES], "actual": actual, "expected": expected}
