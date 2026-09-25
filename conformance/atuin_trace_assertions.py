"""Instantiate the full runner relation against literal native states and exact bindings."""
from __future__ import annotations

from typing import cast
from migration_check.sql_model import Table, lean_string
from atuin_cases import text
from atuin_trace_values import LABELS, NAMES, table_definitions


def cases(body: str, indent: int = 2) -> str:
    """Split the finite database namespace, leaving the absent-table branch explicit."""
    lines = []
    for index, name in enumerate(NAMES):
        lines.extend([f"  by_cases h{index} : name = {lean_string(name)}",
                      "  · subst name", "    " + body.replace("LABEL", LABELS[index]).replace("\n", "\n    ")])
    return "\n".join(" " * (indent - 2) + line for line in lines)


def conforms(prefix: str, schema: str) -> str:
    """Prove all native tables conform; no empty metadata abstraction remains."""
    body = ("refine ⟨rfl, ?_⟩\nintro table present\n"
            f"have equal : table = {prefix}LABEL := by simpa [{prefix}] using present.symm\n"
            f"subst table\nexact ⟨{prefix}LABEL_valid, rfl⟩")
    return f"""
theorem {prefix}_conforms : Conforms {schema} {prefix} := by
  refine ⟨?_, ?_⟩
  · simp [Schema.Valid, {schema}]
    decide +kernel
  intro name
{cases(body)}
  simp [{prefix}, Schema.lookup, Schema.lookupProperties, {schema}, List.find?,
    h0, h1, h2, h3, beq_eq_false_iff_ne.mpr (Ne.symm h0),
    beq_eq_false_iff_ne.mpr (Ne.symm h1), beq_eq_false_iff_ne.mpr (Ne.symm h2),
    beq_eq_false_iff_ne.mpr (Ne.symm h3)]
"""


def assertions(before: tuple[Table, ...], after: tuple[Table, ...], native: dict[str, object],
               *, timing_failure: bool) -> str:
    """The original SQL checksum controls insertion, not an expected record copied unchecked."""
    old = cast(dict[str, object], native["before"])
    final = cast(dict[str, object], native["post_close"])
    metadata = cast(list[dict[str, object]], final["metadata"])
    inserted = metadata[-1]
    elapsed = int(inserted["execution_time"])
    completion = ".timingFailure" if timing_failure else f".success ({elapsed})"
    definitions = table_definitions("before", before, old, after=False)
    definitions += table_definitions("after", after, final, after=True)
    same = "simp [after, recorded, payload, before, Database.set, h0, h1, h2, h3]"
    return "open SqliteVerifier\nset_option maxRecDepth 30000\nset_option maxHeartbeats 10000000\n" + definitions + conforms("before", "Generated.startSchema") + conforms("after", "Generated.nextSchema") + f"""
def config : SqlxConfig := match Generated.profile with
  | .sqlite346Sqlx value => value
  | .sqlite351Autocommit => ⟨⟨0, [], []⟩, []⟩
def completion : CommittedResult := {completion}
def payload : Database := before.set "history" afterHistory
def recorded : Database := payload.set "_sqlx_migrations" afterMetadata
theorem checkedReady : Generated.profile.ready Generated.script before := by
  change SqlxReady config Generated.script before
  refine ⟨?_, ?_, ?_, ?_⟩
  · simp [SqlxConfig.Valid, config, Generated.profile, validRowid] <;> decide +kernel
  · decide +kernel
  · intro name fields member
    simp only [List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨beforeStat1, rfl, rfl, rfl⟩
    · exact ⟨beforeStat4, rfl, rfl, rfl⟩
  · refine ⟨beforeMetadata, rfl, ?_, ?_, ?_⟩ <;> decide +kernel
theorem checkedInsertion : MetadataInserted config.migration beforeMetadata afterMetadata completion.elapsed := by
  refine ⟨rfl, rfl, afterMetadata_valid, ?_, ?_⟩
  · refine ⟨({inserted['rowid']}), {text(str(inserted['installed_on'])).lean().removeprefix('.text ')}, ?_⟩
    decide +kernel
  · unfold validRowid
    decide +kernel
theorem checkedMaintenance : RowsChange statisticsNames recorded after := by
  constructor
  · intro name
{cases('rfl', 4)}
    {same}
  · intro name
{cases('rfl', 4)}
    {same}
  · intro name table present
    exact ((after_conforms.2 name).2 table present).1
  · intro name outside
    simp only [statisticsNames, List.mem_cons, List.mem_singleton, not_or] at outside
    by_cases h0 : name = "_sqlx_migrations"
    · subst name; rfl
    by_cases h1 : name = "history"
    · subst name; rfl
    simp [after, recorded, payload, before, Database.set, h0, h1, outside.1, outside.2]
theorem checkedTrace : ProfileExecutes Generated.profile Generated.script before
    (completion.outcome Generated.script.length after) := by
  apply ProfileExecutes.committed (completion := completion) (payload := payload)
  · have valid : (supportedTableName "history" && supportedColumn
        {{ name := "shell", affinity := .text }} &&
        Column.plain {{ name := "shell", affinity := .text }}) = true := by decide +kernel
    have lookup : before "history" = some beforeHistory := rfl
    have room : ¬beforeHistory.columns.length ≥ maximumColumns := by decide +kernel
    have fresh : beforeHistory.columns.any (fun c => c.name == "shell") = false := by decide +kernel
    simp only [run, runFrom, Generated.script, step, valid, lookup, room, fresh,
      Bool.not_true, Bool.false_eq_true, if_false]
    apply congrArg Outcome.success
    funext name
    by_cases same : name = "history"
    · subst name; decide +kernel
    · simp [payload, Database.set, same]
  · rfl
  · exact checkedInsertion
  · exact checkedMaintenance
#print axioms checkedTrace
#print axioms checkedReady
#print axioms before_conforms
"""
