"""S4's query-output and unique-lookup contracts keep their full formulas and checked proofs.

`compile_checks` compiles fresh consumers of the model bridge and bound, and rejects sorryAx,
ofReduceBool and _native in their axiom reports. The surface companion checks its public wrappers.
"""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean("compiler")]

CHECKS = """
import Belay.Sqlite.Model
open Belay.Sqlite.Model
example (results : List (List (List Value))) :
    (Output.ofResults results).hasRows = true ↔ results ≠ [] ∧ ∀ result ∈ results, result ≠ [] :=
  Output.hasRows_ofResults results
example (results : List (List (List Value))) :
    (Output.ofResults results).hasNoRows = true ↔ results ≠ [] ∧ ∀ result ∈ results, result = [] :=
  Output.hasNoRows_ofResults results
example (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statement : Syntax.Statement) (parameters : List Value) :
    (runScriptStep context clock index connection statement parameters).output =
      match resolveStatement context connection.resolveState statement with
      | .error restriction => .unmodeled restriction.reason
      | .ok (resolved, _) => resolvedStepOutput clock index connection parameters resolved :=
  runScriptStep_output context clock index connection statement parameters
example {keys : List UniqueKey} {table : Table} (unique : table.KeysUnique keys)
    (stored : table.RowsStored) {key : UniqueKey} (member : key ∈ keys)
    {index : Nat} {descending : Bool} {collation : Collation} {column : CatalogColumn}
    (columnAt : table.shape.columns[index]? = some column) (noFilter : key.filter = none)
    (oneTerm : key.terms = [{ term := .column index, descending, collation }])
    (context : Resolved.EvalContext) (value : Resolved.Expr) (cell : Value)
    (constant : ∀ row : List Value, value.eval context row = cell) :
    Resolved.countMatching context
      (some (.compare .eq (some column.affinity) (.column index) value collation)) table ≤ 1 :=
  Table.KeysUnique.countMatching_le_one unique stored member columnAt noFilter oneTerm context value cell constant
#print axioms Output.hasRows_ofResults
#print axioms Output.hasNoRows_ofResults
#print axioms runScriptStep_output
#print axioms Table.KeysUnique.countMatching_le_one
"""


def test_query_output_and_unique_lookup_contracts(tmp_path: Path, lean_sysroot: Path,
                                                lean_libraries: tuple[Path, Path]) -> None:
    """The model contracts for S4 outcomes 2 and 6 elaborate exactly as stated and print checked axioms."""
    output = compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
    assert len([line for line in output.splitlines() if "depends on axioms" in line]) == 4, output
