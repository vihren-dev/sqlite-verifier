"""Check catalog selection in the comparison and prediction consumers of execution traces."""

from pathlib import Path

import pytest

from tests.shared_table_shape_test import compile_checks

pytestmark = [pytest.mark.integration, pytest.mark.kernel,
              pytest.mark.requires_lean("compiler")]

CHECKS = """
import VerifierConformance.Predict
open Belay.Sqlite Belay.Sqlite.Conformance

def shape : CatalogTable := { columns := [{ name := "id", declaredType := none }] }
def table : Table := { shape, rows := [{ rowid := 1, values := [.integer 7] }] }
def catalog (name : String) : Catalog := [{ name, entry := .table shape }]
-- Distinct names make selection of the wrong catalog observable in JSON as well as comparison.
def beforeState : ResolveState := { catalog := catalog "visible", saved := some (catalog "committed") }
def afterState : ResolveState := { catalog := catalog "after" }
def failed : Observation where
  visible := [some table]
  persisted := [some table]
  transactionOpen := true
  error := some (0, .constraintViolation)
def expected : NativeObservation where
  visible := [nativeTableOf beforeState.catalog 0 "visible" table]
  persisted := [nativeTableOf (catalog "committed") 0 "committed" table]
  transactionOpen := true
  primaryCode := 19
  extendedCode := 1299
  phase := some .step

example : compareSteps [beforeState, afterState] 0 [failed] [expected] = .agree := by decide +kernel
example : compareSteps [beforeState, afterState] 0 [failed]
    [{ expected with visible := [] }] = .disagree (some 0) := by decide +kernel
#guard predictedSteps [beforeState, afterState] [{ failed with error := none }, failed] ==
  [stepJson beforeState { failed with error := none }, stepJson beforeState failed]
#guard predictedSteps [beforeState, afterState] [{ failed with error := none }, { failed with error := none }] ==
  [stepJson beforeState { failed with error := none }, stepJson afterState { failed with error := none }]
-- A failure at the second statement keeps the first statement's successful catalog.
#guard predictedSteps [beforeState, afterState, beforeState]
    [{ failed with error := none }, { failed with error := none }, { failed with error := some (1, .constraintViolation) }] ==
  [stepJson beforeState { failed with error := none }, stepJson afterState { failed with error := none },
   stepJson afterState { failed with error := some (1, .constraintViolation) }]
"""


def test_failed_observation_retains_preceding_catalog(tmp_path: Path, lean_sysroot: Path,
        lean_libraries: tuple[Path, Path]) -> None:
    """compareSteps and predictedSteps retain pre-error visible and saved catalogs, including a successful prefix."""
    compile_checks(CHECKS, tmp_path, lean_sysroot, lean_libraries)
