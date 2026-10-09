"""Real Lean checks certify application-key domains and record multiplicity."""

import os
from pathlib import Path

import pytest

from tests.runtime_support import run_command

pytestmark = [pytest.mark.integration, pytest.mark.requires_lean("compiler")]

KEY_CHECKS = """
import SqliteVerifier.ApplicationKeys
open Belay.Sqlite SqliteVerifier

def columns : List Column := [
  { name := "id", affinity := .integer },
  { name := "payload", affinity := .text }]
def first : Table := { columns := columns, rows := [
  ⟨4, [.integer 1, .text [65]]⟩, ⟨8, [.integer 2, .text [66]]⟩] }
def reordered : Table := { first with rows := [
  ⟨900, [.integer 2, .text [66]]⟩, ⟨-5, [.integer 1, .text [65]]⟩] }
def readRecords (table : Table) : ApplicationKeyRows :=
  (projectApplicationRows table ["id"] ["payload"]).getD []

#guard (projectApplicationRows first ["id"] ["payload"]).isSome
#guard (projectApplicationRows reordered ["id"] ["payload"]).isSome
#guard (projectApplicationRows { first with rows := first.rows.take 1 }
  ["id"] ["payload"]).isSome
#guard (projectApplicationRows { first with rows := [
  ⟨4, [.integer 1, .text [90]]⟩, ⟨8, [.integer 2, .text [66]]⟩] }
  ["id"] ["payload"]).isSome
example : applicationKeyPreservation.change (readRecords first) (readRecords reordered) := by
  unfold applicationKeyPreservation
  decide
example : readRecords first ≠ readRecords reordered := by decide
example : ¬ applicationKeyPreservation.change (readRecords first)
  (readRecords { first with rows := first.rows.take 1 }) := by
  unfold applicationKeyPreservation
  decide
example : ¬ applicationKeyPreservation.change (readRecords first)
  (readRecords first ++ readRecords first) := by
  unfold applicationKeyPreservation
  decide
example : ¬ applicationKeyPreservation.change (readRecords first)
  (readRecords { first with rows := [
    ⟨4, [.integer 1, .text [90]]⟩, ⟨8, [.integer 2, .text [66]]⟩] }) := by
  unfold applicationKeyPreservation
  decide

#guard (projectApplicationRows { first with rows := [⟨4, [.null, .text [65]]⟩] }
  ["id"] ["payload"]).isNone
#guard (projectApplicationRows { first with rows := [
  ⟨4, [.integer 1, .text [65]]⟩, ⟨8, [.integer 1, .text [66]]⟩] }
  ["id"] ["payload"]).isNone
#guard (projectApplicationRows first [] ["payload"]).isNone
#guard (projectApplicationRows first ["id", "id"] ["payload"]).isNone
#guard (projectApplicationRows { first with rows := [] } ["missing"] ["payload"]).isNone
#guard (projectApplicationRows { first with rows := [] } ["id"] ["missing"]).isNone
#guard projectApplicationRows { first with rows := [] } ["id"] ["payload"] = some []
#guard (projectApplicationRows { first with rows := [⟨4, [.integer 1]⟩] }
  ["id"] ["payload"]).isNone
#guard (observeApplicationRows "items" ["id"] ["payload"] (fun _ => none)).isNone
#guard (projectApplicationRows first ["id"] []).map (List.map Prod.snd) = some [[], []]
"""


def test_application_keys_preserve_records_and_reject_invalid_domains(
        tmp_path: Path, lean_sysroot: Path, lean_libraries: tuple[Path, Path]) -> None:
    """Compile actual permutation proofs and refusal checks with the current library."""
    source = tmp_path / "ApplicationKeyChecks.lean"
    source.write_text(KEY_CHECKS)
    result = run_command([str(lean_sysroot / "bin/lean"), str(source)], cwd=tmp_path,
        timeout=15, environment={**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_libraries))})
    assert result.returncode == 0, result.diagnostic()
