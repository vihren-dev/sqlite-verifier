"""The statement theorems of the atoms of `Database.Admitted` (ADR 0022, D3, slice 4, part 2) have
their stated formulas and rest only on the standard axioms.

There is one theorem for each atom: `runStatement_rowidsDistinct`, `runStatement_rowsShaped` and
`runStatement_catalogSupported` cover every form of `Resolved.Statement`, and
`runStatement_rowidsInRange`, `runStatement_rowsWide`, `runStatement_rowsStored` and
`runStatement_rowsAliased` cover every form too, with the support check as a hypothesis, also with
foreign key rules and trigger programs (owner decision M: the row engine tests every row that it
writes, `LiteralData.rowAdmitted`).
The check file restates each formula, so a change that weakens a formula (for example a hypothesis
that is dropped, or an atom that changes) fails here, and it refuses `sorryAx`, `ofReduceBool` and
`_native` in the `#print axioms` output (`compile_checks`).
"""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

THEOREMS = [
    "runStatement_rowidsDistinct", "runStatement_rowsShaped", "runStatement_catalogSupported",
    "runStatement_rowidsInRange", "runStatement_rowsWide", "runStatement_rowsStored",
    "runStatement_rowsAliased", "runStatement_tableAtom", "runStatement_plain_rowsOnly",
    "LiteralData.rowAdmitted_iff", "rowidsInRangeLaws", "rowsWideLaws", "rowsStoredLaws", "rowsAliasedLaws",
]

STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
"""The axioms of Lean's logic that a proof of the model may use; any other axiom, such as
`sorryAx` or one that a proof adds, is refused."""

CHECKS = """
import Belay.Sqlite.Model
open Belay.Sqlite.Model
example (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    (database : Database) (distinct : database.RowidsDistinct) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowidsDistinct :=
  runStatement_rowidsDistinct clock counters parameters statement distinct
example (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    (database : Database) (shaped : database.RowsShaped) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsShaped :=
  runStatement_rowsShaped clock counters parameters statement shaped
example (limits : Limits) (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) (database : Database) (valid : database.catalog.Valid limits)
    (next : (statement.applyCatalog database.catalog).Valid limits) :
    (runStatement clock counters parameters statement database).effect.Satisfies
      fun after => after.catalog.Valid limits :=
  runStatement_catalogSupported limits clock counters parameters statement valid next
example (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    (database : Database) (inRange : database.RowidsInRange)
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowidsInRange :=
  runStatement_rowidsInRange clock counters parameters statement inRange ready
example (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    (database : Database) (wide : database.RowsWide)
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsWide :=
  runStatement_rowsWide clock counters parameters statement wide ready
example (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    (database : Database) (stored : database.RowsStored) (wide : database.RowsWide)
    
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsStored :=
  runStatement_rowsStored clock counters parameters statement stored wide ready
example (limits : Limits) (clock : Int) (counters : Counters) (parameters : List Value)
    (statement : Resolved.Statement) (database : Database) (aliased : database.RowsAliased)
    (valid : database.catalog.Valid limits) 
    (ready : (runStatement clock counters parameters statement database).ready = true) :
    (runStatement clock counters parameters statement database).effect.Satisfies Database.RowsAliased :=
  runStatement_rowsAliased limits clock counters parameters statement aliased valid ready
example (shape : CatalogTable) (row : Row) :
    LiteralData.rowAdmitted shape row = true ↔ validRowid row.rowid ∧
      row.values.length = shape.columns.length ∧ row.Stored shape.columns ∧ row.Aliased shape.rowidAlias :=
  LiteralData.rowAdmitted_iff shape row
example : WriteLaws Database.RowidsInRange := rowidsInRangeLaws
example : WriteLaws Database.RowsWide := rowsWideLaws
example : WriteLaws Database.RowsStored := rowsStoredLaws
example : WriteLaws Database.RowsAliased := rowsAliasedLaws
""" + "".join(f"#print axioms {name}\n" for name in THEOREMS)


def test_admitted_atoms_statement_theorems(tmp_path: Path, lean_sysroot: Path,
                                           lean_libraries: tuple[Path, Path]) -> None:
    """Each statement theorem of part 2 compiles with its formula and uses only propext, choice and
    quotients."""
    output = compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
    reports = [line for line in output.splitlines() if "depends on axioms" in line]
    assert len(reports) == len(THEOREMS), output
    for report in reports:
        axioms = report.split("[", 1)[1].rstrip("]").split(", ")
        assert set(axioms) <= STANDARD_AXIOMS, report
