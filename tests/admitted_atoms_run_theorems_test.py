"""The run theorems of the atoms of `Database.Admitted` and the corollary for `Database.Valid` (ADR 0022,
D3, slice 4, part 3) have their stated formulas and rest only on the standard axioms.

There is one theorem of `runSqlFrom`, one of `runSql` and one of `runScriptFrom` for each atom, and the
same three for the bundle `Database.Admitted`. The theorems of `runScriptFrom` have no hypothesis on the
statements of the script: the atoms that need the catalog assume a context in execution mode with the limits
of the invariant, and the resolver gives the conditions. The theorems of `runSqlFrom` and `runSql` assume
the support check `supportedSqlFrom` and, for "catalog supported", "rows aliased" and the bundle, the run
condition `Resolved.Statement.AppliedValid`. The corollary `runScriptFrom_valid` is the form that ADR 0017,
S4 uses. The check file restates each formula, so a change that weakens a formula (for example a hypothesis
that is dropped, or an atom that changes) fails here, and it refuses `sorryAx`, `ofReduceBool` and `_native`
in the `#print axioms` output (`compile_checks`).
"""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

ATOMS = [
    # (name, invariant, parameter of the invariant, the parameter is explicit in the theorems of runSql)
    ("catalogSupported", "Database.CatalogSupported limits", "limits : Limits", True),
    ("rowsShaped", "Database.RowsShaped", "", False),
    ("rowidsDistinct", "Database.RowidsDistinct", "", False),
    ("rowidsInRange", "Database.RowidsInRange", "", False),
    ("rowsWide", "Database.RowsWide", "", False),
    ("rowsStored", "Database.RowsStoredWide", "", False),
    ("rowsAliased", "Database.RowsAliasedSupported limits", "limits : Limits", True),
    ("admitted", "Database.Admitted profile", "profile : Profile", False),
]

THEOREMS = [f"{prefix}_{name}" for name, *_ in ATOMS for prefix in ("runSqlFrom", "runSql", "runScriptFrom")] + [
    "runScriptFrom_keysUnique", "runScriptFrom_notNull", "runScriptFrom_typesFit", "runScriptFrom_checksHold",
    "runScriptFrom_constraintAtoms", "runScriptFrom_valid", "runScriptStep_valid", "Database.valid_empty", "Database.valid_iff",
]

STANDARD_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
"""The axioms of Lean's logic that a proof of the model may use; any other axiom, such as
`sorryAx` or one that a proof adds, is refused."""


def atom_checks(name: str, invariant: str, parameter: str, explicit: bool) -> str:
    """The restated formulas of the three run theorems of one atom. An atom with a parameter needs the
    catalog: its theorems of `runSqlFrom` and `runSql` ask for the run condition `AppliedValid`, and its
    theorem of `runScriptFrom` asks for the mode and the limits of the context."""
    argument = parameter.split(" :")[0]
    needs_catalog = bool(parameter)
    limits = "profile.limits" if argument == "profile" else "limits"
    binder = f"({parameter}) " if explicit else (f"{{{parameter}}} " if parameter else "")
    passed = f"{argument} " if explicit else ""
    implicit = f"{{{parameter}}} " if parameter else ""
    applied = f"Resolved.Statement.AppliedValid {limits}"
    sql_from_condition = (f"\n    (conditions : RunConditionsWith ({applied}) position script state)"
                          if needs_catalog else "")
    sql_condition = (f"\n    (conditions : RunConditionsWith ({applied}) 0 script {{ database }})"
                     if needs_catalog else "")
    script_hypotheses = (f"\n    (execution : context.mode = .execution) (same : context.profile.limits = {limits})"
                         if needs_catalog else "")
    return f"""
example {binder}(position : Nat) (script : List (Resolved.Statement × List Value)) {{state : SqlState}}
    (holds : state.Holds ({invariant}))
    (supported : supportedSqlFrom position script state = true){sql_from_condition} :
    (runSqlFrom position script state).Holds ({invariant}) :=
  runSqlFrom_{name} {passed}position script holds supported{" conditions" if needs_catalog else ""}
example {binder}(script : List (Resolved.Statement × List Value)) {{database : Database}}
    (holds : ({invariant}) database) (supported : supportedSqlFrom 0 script {{ database }} = true){sql_condition} :
    (runSql script database).Holds ({invariant}) :=
  runSql_{name} {passed}script holds supported{" conditions" if needs_catalog else ""}
example {implicit}(context : ResolveContext) (clock : Option Clock) (index : Nat) {{connection : Connection}}
    (script : List (Syntax.Statement × List Value)){script_hypotheses}
    (holds : connection.state.Holds ({invariant})) :
    (runScriptFrom context clock index connection script).connection.state.Holds ({invariant}) :=
  runScriptFrom_{name} context clock index script{" execution same" if needs_catalog else ""} holds
"""


CHECKS = "\nimport Belay.Sqlite.Model\nopen Belay.Sqlite.Model" + "".join(
    atom_checks(*atom) for atom in ATOMS) + """
example {profile : Profile} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.Valid profile)) :
    (runScriptFrom context clock index connection script).connection.state.Holds (Database.Valid profile) :=
  runScriptFrom_valid context clock index script execution same holds
example {profile : Profile} (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (statement : Syntax.Statement) (values : List Value)
    (execution : context.mode = .execution) (same : context.profile.limits = profile.limits)
    (holds : connection.state.Holds (Database.Valid profile)) {output : Output} {next : Connection}
    (continued : runScriptStep context clock index connection statement values = .continued output next) :
    next.state.Holds (Database.Valid profile) :=
  runScriptStep_valid context clock index statement values execution same holds continued
example (profile : Profile) : (({} : Database)).Valid profile := Database.valid_empty profile
example {profile : Profile} {database : Database} :
    database.Valid profile ↔ database.AdmittedWith profile Database.ConstraintAtoms := Database.valid_iff
""" + "".join(f"#print axioms {name}\n" for name in THEOREMS)


def test_admitted_atoms_run_theorems(tmp_path: Path, lean_sysroot: Path,
                                     lean_libraries: tuple[Path, Path]) -> None:
    """Each run theorem of part 3 compiles with its formula and uses only propext, choice and quotients."""
    output = compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
    reports = [line for line in output.splitlines() if "depends on axioms" in line]
    assert len(reports) == len(THEOREMS), output
    for report in reports:
        axioms = report.split("[", 1)[1].rstrip("]").split(", ")
        assert set(axioms) <= STANDARD_AXIOMS, report
