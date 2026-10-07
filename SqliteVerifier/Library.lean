import SqliteVerifier.ContractProofs
import Belay.Sqlite.ModelFacts

set_option doc.verso true

/-! Application interpretations use structural model facts and retain flexible logical contracts. -/

open Belay.Sqlite

namespace SqliteVerifier

/-- Ordered physical rowids and optional projected cells. Use
{lean}`([] : LogicalRows)` for no rows; a missing cell differs from observed NULL. -/
abbrev LogicalRows := List (Int × List (Option Value))

/-- Project the requested fields of a stored table, retaining row order and
rowids. An absent table yields {name}`Option.none`; a present empty table yields
{lean}`(some [] : Option LogicalRows)`, so lost tables cannot look empty. -/
def observeTable (name : String) (fields : List String) (database : Database) : Option LogicalRows :=
  (database name).map (·.project fields)

/-- Build an {name}`Interpretation` whose invariant requires {name}`Conforms`
and a table stored at the selected name that satisfies {name}`Covers` for all
requested fields. Observation uses {name}`observeTable`. Use an empty field
list to observe rowids only; the caller proves the logical contract's validity. -/
def projectedInterpretation (schema : Schema) (name : String) (fields : List String) :
    Interpretation LogicalRows where
  invariant database := Conforms schema database ∧
    ∃ table, database name = some table ∧ Covers table fields
  observe := observeTable name fields

/-- Give every failure position and reason an empty schema and an interpretation
with false invariant and absent observation. Use this for success-only proofs;
the verification conditions still require proving modeled failures unreachable. -/
def unreachableFailures : FailureRepresentation Logical where
  schema := fun _ _ => []
  interpretation := fun _ _ => ⟨fun _ => False, fun _ => none⟩

/-- For every logical contract, failure position and reason, the corresponding
{name}`unreachableFailures` representation is sound. Every database obligation
is vacuous because its invariant is false; this does not establish a failure
invariant. The proof eliminates that impossible assumption. -/
theorem unreachableFailures_sound (contract : LogicalContract Logical) (position reason) :
    SoundRepresentation contract ((unreachableFailures (Logical := Logical)).schema position reason)
      (unreachableFailures.interpretation position reason) := by
  intro database impossible
  exact False.elim impossible

/-- For every contract, schema, name and field list, assume the projection of
every valid table covering those fields satisfies the contract's validity.
Then {name}`projectedInterpretation` is a {name}`SoundRepresentation`. An empty
field list still requires that validity premise for its rowid-only projections.
The proof extracts the stored valid table and applies the supplied premise. -/
theorem projectedInterpretation_sound (contract : LogicalContract LogicalRows)
    (schema : Schema) (name : String) (fields : List String)
    (valid : ∀ table, table.Valid → Covers table fields → contract.valid (table.project fields)) :
    SoundRepresentation contract schema (projectedInterpretation schema name fields) := by
  intro database invariant
  obtain ⟨conforms, table, present, covered⟩ := invariant
  exact ⟨conforms, table.project fields, by simp [projectedInterpretation, observeTable, present],
    valid table ((conforms.2 name).2 table present).1 covered⟩


end SqliteVerifier
