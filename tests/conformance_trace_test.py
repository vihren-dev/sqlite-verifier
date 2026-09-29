"""Kernel-check transaction trace observations independently of the trace evaluator."""

import os
from pathlib import Path
import subprocess

import pytest


pytestmark = [pytest.mark.integration, pytest.mark.conformance, pytest.mark.kernel,
              pytest.mark.requires_lean]


def test_production_trace(tmp_path: Path, lean_sysroot: Path, lean_library: Path) -> None:
    """Snapshots preserve writes, commits, rollbacks, failure positions and stop-on-error."""
    proof = tmp_path / "TraceChecks.lean"
    proof.write_text('''import SqliteVerifier.ConformanceTrace
open SqliteVerifier SqliteVerifier.Conformance

def columns : List Column := [{ name := "value", affinity := .integer }]
def original : Table := {
  columns := columns
  rows := [⟨-4, [.integer 7]⟩, ⟨22, [.integer 8]⟩]
  properties := { uniqueKeys := [["value"]] } }
def changed : Table := { original with rows := original.rows ++ [⟨23, [.integer 9]⟩] }
def initial : Database := fun name =>
  if name = "records" then some { original with rows := original.rows.reverse } else none
def names := ["absent", "records"]
def before : Tables := [("absent", none), ("records", some original)]
def after : Tables := [("absent", none), ("records", some changed)]
def idle : Observation := ⟨before, before, false, none⟩
def begun : Observation := ⟨before, before, true, none⟩
def written : Observation := ⟨after, before, true, none⟩
def committed : Observation := ⟨after, after, false, none⟩
def insertNew : Statement := .insert "records" ["value"] [.integer 9]
def writeScript : List Statement := [.beginTransaction, insertNew]

theorem pending_write : trace names writeScript initial = [idle, begun, written] := by
  decide +kernel
theorem explicit_commit : trace names (writeScript ++ [.commit]) initial =
    [idle, begun, written, committed] := by decide +kernel
theorem explicit_rollback : trace names (writeScript ++ [.rollback]) initial =
    [idle, begun, written, idle] := by decide +kernel
theorem constraint_halts : trace names (writeScript ++ [insertNew, .commit]) initial =
    [idle, begun, written, { written with error := some (2, .constraintViolation) }] := by
  decide +kernel
theorem nested_begin_halts : trace names (writeScript ++ [.beginTransaction, .rollback]) initial =
    [idle, begun, written, { written with error := some (2, .transactionAlreadyActive) }] := by
  decide +kernel
theorem empty_trace : trace names [] initial = [idle] := by decide +kernel
theorem no_transaction : trace names [.commit, insertNew] initial =
    [idle, { idle with error := some (0, .noActiveTransaction) }] := by decide +kernel
#print axioms trace_final
#print axioms pending_write
#print axioms explicit_commit
#print axioms explicit_rollback
#print axioms constraint_halts
#print axioms nested_begin_halts
#print axioms empty_trace
#print axioms no_transaction
''')
    result = subprocess.run([str(lean_sysroot / "bin/lean"), str(proof)],
                            env={**os.environ, "LEAN_PATH": str(lean_library)},
                            text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    for forbidden in ("sorryAx", "ofReduceBool", "_native"):
        assert forbidden not in result.stdout, result.stdout
