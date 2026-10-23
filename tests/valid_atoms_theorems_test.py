"""The theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3) have
their stated formulas and rest only on the standard axioms.

The statement theorems, the run theorems of `runSqlFrom`, `runSql` and `runScriptFrom`, and the
corollary for the four constraint atoms are in the root import of the model. The check file restates
each formula, so a change that weakens a formula fails here, and it refuses `sorryAx`,
`ofReduceBool` and `_native` in the `#print axioms` output (`compile_checks`).
"""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

THEOREMS = [
    "runStatement_notNull", "runSqlFrom_notNull", "runSql_notNull", "runScriptFrom_notNull",
    "runStatement_typesFit", "runSqlFrom_typesFit", "runSql_typesFit", "runScriptFrom_typesFit",
    "runStatement_checksHold", "runSqlFrom_checksHold", "runSql_checksHold", "runScriptFrom_checksHold",
    "runSqlFrom_constraintAtoms", "runSql_constraintAtoms", "runScriptFrom_constraintAtoms",
]

STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
"""The axioms of Lean's logic that a proof of the model may use; any other axiom, such as
`sorryAx` or one that a proof adds, is refused."""

CHECKS = """
import Belay.Sqlite.Model
open Belay.Sqlite.Model
example (clock : Int) (parameters : List Value) (statement : Resolved.Statement) {database : Database}
    (holds : Database.NotNull database) (condition : statement.NotNullCondition database) :
    (runStatement clock parameters statement database).effect.Satisfies Database.NotNull :=
  runStatement_notNull clock parameters statement holds condition
example (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.NotNull) (conditions : NotNullRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.NotNull :=
  runSqlFrom_notNull position script holds conditions
example (script : List (Resolved.Statement × List Value)) {database : Database} (holds : Database.NotNull database)
    (conditions : NotNullRunConditions 0 script { database }) : (runSql script database).Holds Database.NotNull :=
  runSql_notNull script holds conditions
example (context : ResolveContext) (clock : Option Clock) (index : Nat) {connection : Connection}
    (script : List (Syntax.Statement × List Value)) (holds : connection.state.Holds Database.NotNull)
    (conditions : NotNullScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.NotNull :=
  runScriptFrom_notNull context clock index script holds conditions
example (clock : Int) (parameters : List Value) (statement : Resolved.Statement) {database : Database}
    (holds : Database.TypesFit database) (condition : statement.TypesFitCondition database) :
    (runStatement clock parameters statement database).effect.Satisfies Database.TypesFit :=
  runStatement_typesFit clock parameters statement holds condition
example (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.TypesFit) (conditions : TypesFitRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.TypesFit :=
  runSqlFrom_typesFit position script holds conditions
example (script : List (Resolved.Statement × List Value)) {database : Database} (holds : Database.TypesFit database)
    (conditions : TypesFitRunConditions 0 script { database }) : (runSql script database).Holds Database.TypesFit :=
  runSql_typesFit script holds conditions
example (context : ResolveContext) (clock : Option Clock) (index : Nat) {connection : Connection}
    (script : List (Syntax.Statement × List Value)) (holds : connection.state.Holds Database.TypesFit)
    (conditions : TypesFitScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.TypesFit :=
  runScriptFrom_typesFit context clock index script holds conditions
example (clock : Int) (parameters : List Value) (statement : Resolved.Statement) {database : Database}
    (holds : Database.ChecksHold database) (condition : statement.ChecksHoldCondition database) :
    (runStatement clock parameters statement database).effect.Satisfies Database.ChecksHold :=
  runStatement_checksHold clock parameters statement holds condition
example (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.ChecksHold) (conditions : ChecksHoldRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.ChecksHold :=
  runSqlFrom_checksHold position script holds conditions
example (script : List (Resolved.Statement × List Value)) {database : Database} (holds : Database.ChecksHold database)
    (conditions : ChecksHoldRunConditions 0 script { database }) : (runSql script database).Holds Database.ChecksHold :=
  runSql_checksHold script holds conditions
example (context : ResolveContext) (clock : Option Clock) (index : Nat) {connection : Connection}
    (script : List (Syntax.Statement × List Value)) (holds : connection.state.Holds Database.ChecksHold)
    (conditions : ChecksHoldScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.ChecksHold :=
  runScriptFrom_checksHold context clock index script holds conditions
example (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.ConstraintAtoms) (conditions : AtomsRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.ConstraintAtoms :=
  runSqlFrom_constraintAtoms position script holds conditions
example (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : database.ConstraintAtoms) (conditions : AtomsRunConditions 0 script { database }) :
    (runSql script database).Holds Database.ConstraintAtoms :=
  runSql_constraintAtoms script holds conditions
example (context : ResolveContext) (clock : Option Clock) (index : Nat) {connection : Connection}
    (script : List (Syntax.Statement × List Value)) (holds : connection.state.Holds Database.ConstraintAtoms)
    (conditions : AtomsScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.ConstraintAtoms :=
  runScriptFrom_constraintAtoms context clock index script holds conditions
""" + "".join(f"#print axioms {name}\n" for name in THEOREMS)


def test_valid_atoms_theorems(tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Each theorem of the three atoms and of their corollary compiles with its formula and uses only
    propext, choice and quotients."""
    output = compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
    reports = [line for line in output.splitlines() if "depends on axioms" in line]
    assert len(reports) == len(THEOREMS), output
    for report in reports:
        axioms = report.split("[", 1)[1].rstrip("]").split(", ")
        assert set(axioms) <= STANDARD_AXIOMS, report
