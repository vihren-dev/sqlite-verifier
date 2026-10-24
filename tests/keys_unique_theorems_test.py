"""The theorems of the atom "keys unique" (ADR 0022, D3, slice 2) have their stated formulas and
rest only on the standard axioms.

The statement theorem `runStatement_keysUnique`, the run theorems `runSqlFrom_keysUnique`,
`runSql_keysUnique` and `runScriptFrom_keysUnique`, and the lookup lemma
`Database.KeysUnique.lookup` are in the root import of the model. The check file restates each
formula, so a change that weakens a formula fails here, and it refuses `sorryAx`,
`ofReduceBool` and `_native` in the `#print axioms` output (`compile_checks`).
"""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

THEOREMS = ["runStatement_keysUnique", "runSqlFrom_keysUnique", "runSql_keysUnique",
            "runScriptFrom_keysUnique", "Database.KeysUnique.lookup"]

STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
"""The axioms of Lean's logic that a proof of the model may use; any other axiom, such as
`sorryAx` or one that a proof adds, is refused."""

CHECKS = """
import Belay.Sqlite.Model
open Belay.Sqlite.Model
example (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    {database : Database} (unique : database.KeysUnique) (condition : statement.KeysCondition database) :
    (runStatement clock counters parameters statement database).effect.KeysUnique :=
  runStatement_keysUnique clock counters parameters statement unique condition
example (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (unique : state.KeysUnique) (conditions : RunConditions position script state) :
    (runSqlFrom position script state).KeysUnique :=
  runSqlFrom_keysUnique position script unique conditions
example (script : List (Resolved.Statement × List Value)) {database : Database} (unique : database.KeysUnique)
    (conditions : RunConditions 0 script { database }) : (runSql script database).KeysUnique :=
  runSql_keysUnique script unique conditions
example (context : ResolveContext) (clock : Option Clock) (index : Nat) {connection : Connection}
    (script : List (Syntax.Statement × List Value)) (unique : connection.state.KeysUnique)
    (conditions : ScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.KeysUnique :=
  runScriptFrom_keysUnique context clock index script unique conditions
example {database : Database} (unique : database.KeysUnique) {position : Nat} {table : Table}
    (found : database.table position = some table) {key : UniqueKey}
    (member : key ∈ database.catalog.uniqueKeys position table.shape) (probe : Row) :
    (table.rows.filter fun row => LiteralData.keyEqual key row probe).length ≤ 1 :=
  Database.KeysUnique.lookup unique found member probe
""" + "".join(f"#print axioms {name}\n" for name in THEOREMS)


def test_keys_unique_theorems(tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Each theorem of keys unique compiles with its formula and uses only propext, choice and quotients."""
    output = compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
    reports = [line for line in output.splitlines() if "depends on axioms" in line]
    assert len(reports) == len(THEOREMS), output
    for report in reports:
        axioms = report.split("[", 1)[1].rstrip("]").split(", ")
        assert set(axioms) <= STANDARD_AXIOMS, report
