"""Compare omitted INSERT values from fullCells with pinned native SQLite storage."""

import json
from pathlib import Path

import pytest

from belay.sqlite.quoted_text import quoted_string
from conformance.case_format import Json, cell_wire
from conformance.native_connection import Connection, NativeError, library_path
from conformance.native_library import library_binary, load_library
from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler"),
              pytest.mark.requires_native("sqlite3", "sqlite3-3.46.0")]

CASES = [
    ("NULL", ".null"), ("7", '.numeric "7"'), ("1.5", '.numeric "1.5"'),
    ("'7'", ".string [55]"), ("'λ'", ".string [206, 187]"),
    ("X'00ff'", ".blob [0, 255]"),
    ("-9223372036854775808", '.negate (.numeric "9223372036854775808")'),
    ("+7", '.positive (.numeric "7")'),
    ("TRUE", '.identifier "TRUE" false'), ("FaLsE", '.identifier "FaLsE" false'),
    ("hello", '.identifier "hello" false'), ('"true"', '.identifier "true" true'),
]
"""Written defaults exercise literal classes, signed boundaries and identifier quoting."""


AFFINITIES = ["INTEGER", "NUMERIC", "REAL", "TEXT", "BLOB"]
"""Each affinity of the column; one Lean program checks all of them for a version."""


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_omitted_default_values(version: str, tmp_path: Path,
        lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """fullCells evaluates omitted defaults and applies the delivered storeValue conversion,
    for each affinity of `AFFINITIES`.

    SQL catalog admission and ADD COLUMN execution are separate acceptance checks.
    """
    connection = Connection(load_library(library_path(library_binary(version)), version),
                            tmp_path / "native.db")
    expected: list[list[list[Json]]] = []
    try:
        for affinity in AFFINITIES:
            per_affinity: list[list[Json]] = []
            for index, (sql, _) in enumerate(CASES):
                table = f"t_{affinity}_{index}"
                connection.execute_script(
                    f"CREATE TABLE {table}(id BLOB, added {affinity} DEFAULT {sql});"
                    f"INSERT INTO {table}(id) VALUES(7);")
                rows = connection.query(f"SELECT id,added FROM {table};")
                assert len(rows) == 1, (sql, rows)
                per_affinity.append([cell_wire(cell) for cell in rows[0]])
            expected.append(per_affinity)
    finally:
        connection.close()
    expressions = ", ".join(f"⟨({expression}), {quoted_string(sql)}⟩" for sql, expression in CASES)
    affinities = ", ".join(quoted_string(affinity) for affinity in AFFINITIES)
    source = f'''import Belay.Sqlite.Codec
import Belay.Sqlite.Resolution.ClockRows
open Belay.Sqlite Lean
#eval do
  let inputs : List Syntax.DefaultExpression := [{expressions}]
  let tables ← [{affinities}].mapM fun affinity => inputs.mapM fun expression => do
    let columns : List CatalogColumn := [{{name := "id", declaredType := some "BLOB"}},
      {{name := "added", declaredType := some affinity, defaultValue := some expression}}]
    IO.ofExcept (((fullCells columns [0] [(.integer 7, none)]).map fun (cells : List RowCell) => cells.map Prod.fst).mapError reprStr)
  IO.println (toJson tables).compress
'''
    actual = json.loads(compile_checks(source, tmp_path, lean_sysroot, lean_libraries))
    assert actual == expected, {"defaults": [sql for sql, _ in CASES], "actual": actual, "expected": expected}


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
@pytest.mark.parametrize("negated", [False, True])
def test_oversized_hex_default_prepare_error(version: str, negated: bool, tmp_path: Path,
        lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """fullCells preserves SQLite's prepare error for an oversized hexadecimal default."""
    token = "0x1ffffffffffffffff"
    sql = ("-" if negated else "") + token
    connection = Connection(load_library(library_path(library_binary(version)), version),
                            tmp_path / "native.db")
    try:
        connection.execute_script(f"CREATE TABLE t(id BLOB, added BLOB DEFAULT {sql});")
        with pytest.raises(NativeError) as failure:
            connection.query("INSERT INTO t(id) VALUES(7);")
        error = failure.value
        assert error.code == 1 and error.phase == "prepare"
        expected = [error.phase, str(error)]
    finally:
        connection.close()
    expression = f'.numeric "{token}"'
    if negated:
        expression = f".negate ({expression})"
    source = f'''import Belay.Sqlite.Codec
import Belay.Sqlite.Resolution.ClockRows
import Belay.Sqlite.Resolution.Messages
open Belay.Sqlite Lean
#eval do
  let columns : List CatalogColumn := [{{name := "id", declaredType := none}},
    {{name := "added", declaredType := none, defaultValue := some ⟨({expression}), {quoted_string(sql)}⟩}}]
  match fullCells columns [0] [(.integer 7, none)] with
  | .error (.prepare error) =>
    IO.println (toJson ["prepare", error.message]).compress
  | _ => throw (IO.userError "expected the default's preparation error")
'''
    assert json.loads(compile_checks(source, tmp_path, lean_sysroot, lean_libraries)) == expected
