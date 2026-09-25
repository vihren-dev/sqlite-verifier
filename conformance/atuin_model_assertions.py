"""Kernel assertions for payload-only comparisons with independently expected cells."""
from __future__ import annotations

import re
from migration_check.sql_model import Table
from atuin_cases import lean_rows


def audit_axioms(output: str, names: set[str]) -> dict[str, list[str]]:
    """Require the exact named theorem set and the gate's permitted axiom whitelist."""
    rows = re.findall(r"'([^']+)' depends on axioms: \[([^\]]*)\]", output)
    actual = {name: [item.strip() for item in axioms.split(",") if item.strip()]
              for name, axioms in rows}
    allowed = {"propext", "Classical.choice", "Quot.sound"}
    if len(rows) != len(names) or set(actual) != names or any(set(items) - allowed for items in actual.values()):
        raise AssertionError(("Named theorem/axiom audit mismatch", actual, names))
    return actual


def assertions(count: int, expected: Table) -> str:
    """Use the model only for execution; expected output comes from the native schema and fixture."""
    return f"""
open SqliteVerifier
set_option maxRecDepth 30000
set_option maxHeartbeats 5000000
def initialHistory : Table := {{
  columns := (Generated.startSchema.lookup "history").getD []
  properties := (Generated.startSchema.lookupProperties "history").getD {{}}
  rows := {lean_rows(count)} }}
def before : Database := Generated.startSchema.emptyDatabase.set "history" initialHistory
def expectedDeclaration : TableSchema := {expected.lean()}
def expectedHistory : Table := {{
  columns := expectedDeclaration.columns, properties := expectedDeclaration.properties
  rows := {lean_rows(count, after=True)} }}
def observed := run Generated.script before
def succeeded : Outcome → Bool | .success _ => true | .failure _ _ _ => false
theorem checkedSchemaValidity : Generated.startSchema.Valid := by
  simp [Schema.Valid, Generated.startSchema]
  decide +kernel
theorem checkedWitnessValidity : initialHistory.Valid := by
  simp [Table.Valid, initialHistory, Generated.startSchema, Schema.lookup,
    Schema.lookupProperties, validRowid]
  decide +kernel
theorem checkedConformance : Conforms Generated.startSchema before := by
  apply (Generated.startSchema.emptyDatabase_conforms checkedSchemaValidity).set
    checkedSchemaValidity checkedWitnessValidity
  · intro other
    by_cases same : other = "history"
    · subst other; decide +kernel
    · simp [same]
  · intro other
    by_cases same : other = "history"
    · subst other; decide +kernel
    · simp [same]
theorem checkedOutcome : succeeded observed = true := by decide +kernel
theorem checkedHistory : observed.database "history" = some expectedHistory := by decide +kernel
example : Generated.nextSchema.lookup "history" = some expectedDeclaration.columns := by decide +kernel
example : Generated.nextSchema.lookupProperties "history" = some expectedDeclaration.properties := by decide +kernel
example : observed.database "_sqlx_migrations" = before "_sqlx_migrations" := by decide +kernel
example : observed.database "sqlite_stat1" = before "sqlite_stat1" := by decide +kernel
example : observed.database "sqlite_stat4" = before "sqlite_stat4" := by decide +kernel
#print axioms checkedHistory
#print axioms checkedConformance
"""
