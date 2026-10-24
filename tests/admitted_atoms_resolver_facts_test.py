"""The resolver facts of the atoms of `Database.Admitted` (ADR 0022, D3, slice 4, part 1) have their
stated formulas and rest only on the standard axioms.

The facts say that CREATE TABLE, CREATE INDEX, CREATE TRIGGER, ADD COLUMN and DROP give a catalog that
satisfies `Catalog.Valid`, that `resolveStatement` and `resolve` keep it, and that a valid or admitted
database meets the conditions of ADD COLUMN and DROP. The check file restates each formula, so a change
that weakens a formula fails here, and it refuses `sorryAx`, `ofReduceBool` and `_native` in the
`#print axioms` output (`compile_checks`).
"""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

THEOREMS = [
    "resolveCreateTable_valid", "resolveCreateIndex_valid", "resolveCreateTrigger_valid",
    "resolveAddColumn_valid", "resolveAddColumn_strictDefaultFits",
    "resolveDropTable_valid", "resolveDropIndex_valid", "resolveDropTrigger_valid",
    "resolveDropTable_closed", "resolveDropIndex_closed", "resolveDropTrigger_closed",
    "resolveStatement_valid", "resolve_valid",
    "Database.addColumnCondition_of_admitted", "Database.checksReadBelowAt_of_valid",
    "Database.rowsWideAt_of_admitted", "Database.strictDefaultFitsAt_of_fits",
    "Catalog.Valid.uniqueKeys_readsBelow",
]

STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
"""The axioms of Lean's logic that a proof of the model may use; any other axiom, such as
`sorryAx` or one that a proof adds, is refused."""

CHECKS = """
import Belay.Sqlite.Model
open Belay.Sqlite.Model
example (context : ResolveContext) (catalog after : Catalog) (name : Identifier)
    (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (options : Syntax.TableOptions) (statement : Resolved.Statement)
    (valid : catalog.Valid context.profile.limits) (execution : context.mode = .execution)
    (ok : resolveCreateTable context catalog name columns constraints options = .ok (statement, after)) :
    after.Valid context.profile.limits :=
  resolveCreateTable_valid context catalog after name columns constraints options statement valid execution ok
example (context : ResolveContext) (catalog after : Catalog) (name : Identifier) (unique : Bool)
    (tableName : Identifier) (terms : List Syntax.OrderTerm) (filter : Option Syntax.Expr)
    (statement : Resolved.Statement) (valid : catalog.Valid context.profile.limits)
    (ok : resolveCreateIndex context catalog name unique tableName terms filter = .ok (statement, after)) :
    after.Valid context.profile.limits :=
  resolveCreateIndex_valid context catalog after name unique tableName terms filter statement valid ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifNotExists : Bool)
    (trigger : CatalogTrigger) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveCreateTrigger catalog name ifNotExists trigger = .ok (statement, after)) : after.Valid limits :=
  resolveCreateTrigger_valid limits catalog after name ifNotExists trigger statement valid ok
example (context : ResolveContext) (catalog after : Catalog) (tableName : Identifier)
    (definition : Syntax.ColumnDefinition) (statement : Resolved.Statement)
    (valid : catalog.Valid context.profile.limits)
    (ok : resolveAddColumn context catalog tableName definition = .ok (statement, after)) :
    after.Valid context.profile.limits :=
  resolveAddColumn_valid context catalog after tableName definition statement valid ok
example (context : ResolveContext) (catalog after : Catalog) (tableName : Identifier)
    (definition : Syntax.ColumnDefinition) (position : Nat) (column : CatalogColumn)
    (ok : resolveAddColumn context catalog tableName definition = .ok (.addColumn position column, after)) :
    strictDefaultFits column = true :=
  resolveAddColumn_strictDefaultFits context catalog after tableName definition position column ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifExists : Bool)
    (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropTable catalog name ifExists = .ok (statement, after)) : after.Valid limits :=
  resolveDropTable_valid limits catalog after name ifExists statement valid ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifExists : Bool)
    (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropIndex catalog name ifExists = .ok (statement, after)) : after.Valid limits :=
  resolveDropIndex_valid limits catalog after name ifExists statement valid ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifExists : Bool)
    (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropTrigger catalog name ifExists = .ok (statement, after)) : after.Valid limits :=
  resolveDropTrigger_valid limits catalog after name ifExists statement valid ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifExists : Bool)
    (positions : List Nat) (valid : catalog.Valid limits)
    (ok : resolveDropTable catalog name ifExists = .ok (.drop positions, after)) : catalog.DropClosed positions :=
  resolveDropTable_closed limits catalog after name ifExists positions valid ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifExists : Bool)
    (positions : List Nat) (valid : catalog.Valid limits)
    (ok : resolveDropIndex catalog name ifExists = .ok (.drop positions, after)) : catalog.DropClosed positions :=
  resolveDropIndex_closed limits catalog after name ifExists positions valid ok
example (limits : Limits) (catalog after : Catalog) (name : Identifier) (ifExists : Bool)
    (positions : List Nat) (valid : catalog.Valid limits)
    (ok : resolveDropTrigger catalog name ifExists = .ok (.drop positions, after)) : catalog.DropClosed positions :=
  resolveDropTrigger_closed limits catalog after name ifExists positions valid ok
example (context : ResolveContext) (state next : ResolveState) (statement : Syntax.Statement)
    (resolved : Resolved.Statement) (execution : context.mode = .execution)
    (valid : state.Valid context.profile.limits)
    (ok : resolveStatement context state statement = .ok (resolved, next)) :
    next.Valid context.profile.limits :=
  resolveStatement_valid context state next statement resolved execution valid ok
example (context : ResolveContext) (catalog after : Catalog) (script : List Syntax.Statement)
    (statements : List Resolved.Statement) (execution : context.mode = .execution)
    (valid : catalog.Valid context.profile.limits)
    (ok : resolve context catalog script = .resolved statements after) :
    after.Valid context.profile.limits :=
  resolve_valid context catalog after script statements execution valid ok
example (profile : Profile) (database : Database) (admitted : database.Admitted profile) (target : Nat) :
    database.AddColumnCondition target :=
  Database.addColumnCondition_of_admitted admitted target
example (limits : Limits) (database : Database) (valid : database.catalog.Valid limits) (target : Nat) :
    database.ChecksReadBelowAt target :=
  Database.checksReadBelowAt_of_valid valid target
example (profile : Profile) (database : Database) (admitted : database.Admitted profile) (target : Nat) :
    database.RowsWideAt target :=
  Database.rowsWideAt_of_admitted admitted target
example (database : Database) (target : Nat) (column : CatalogColumn) (fits : strictDefaultFits column = true) :
    database.StrictDefaultFitsAt target column :=
  Database.strictDefaultFitsAt_of_fits fits
example (limits : Limits) (catalog : Catalog) (valid : catalog.Valid limits) (position : Nat)
    (shape : CatalogTable) (present : catalog.tableAt position = some shape) :
    ∀ key ∈ catalog.uniqueKeys position shape, key.readsBelow shape.columns.length = true :=
  valid.uniqueKeys_readsBelow present
""" + "".join(f"#print axioms {name}\n" for name in THEOREMS)


def test_admitted_atoms_resolver_facts(tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Each resolver fact of part 1 compiles with its formula and uses only propext, choice and
    quotients."""
    output = compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
    reports = [line for line in output.splitlines() if "depends on axioms" in line]
    assert len(reports) == len(THEOREMS), output
    for report in reports:
        axioms = report.split("[", 1)[1].rstrip("]").split(", ")
        assert set(axioms) <= STANDARD_AXIOMS, report
