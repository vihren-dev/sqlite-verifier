import SqliteVerifier.Library

set_option doc.verso true

/-! Rowid-free application observations let users preserve business records
through reordered storage. The permutation convenience is built over the
general {name}`SqliteVerifier.Interpretation` and
{name}`SqliteVerifier.LogicalContract` constructors. -/

open Belay.Sqlite

namespace SqliteVerifier

/-- Rowid-free records: each pair contains an ordered application-key tuple
and an ordered protected-cell tuple. Key identity uses exact tagged {name}`Value`
equality. Use {lean}`([] : ApplicationKeyRows)` for no records. -/
abbrev ApplicationKeyRows := List (List Value × List Value)

/-- For every record, its key is nonempty and contains no {name}`Value.null`.
All key tuples are distinct. With no records these requirements are vacuous.
This is logical tagged-value identity; native SQL comparison truth is separate. -/
def ApplicationKeyRows.Valid (rows : ApplicationKeyRows) : Prop :=
  (rows.map Prod.fst).Nodup ∧ ∀ record ∈ rows, record.1 ≠ [] ∧ .null ∉ record.1

/-- Decide {name}`ApplicationKeyRows.Valid` by finite exact key comparisons.
This lets the observation reject invalid keys during computation. -/
instance ApplicationKeyRows.decidableValid (rows : ApplicationKeyRows) : Decidable rows.Valid :=
  inferInstanceAs (Decidable ((rows.map Prod.fst).Nodup ∧
    ∀ record ∈ rows, record.1 ≠ [] ∧ .null ∉ record.1))

/-- Read all records using the requested key and protected fields, dropping
physical rowids. Require a nonempty, distinct key-name list and presence of
every requested column, even for an empty table. Return {name}`Option.none`
for a missing cell, NULL key or duplicate logical key; no row is discarded
or merged. Use an empty protected-field list to observe only application keys.
SQL affinity and collation are not evaluated by this logical projection. -/
def projectApplicationRows (table : Table) (keyNames fields : List String) :
    Option ApplicationKeyRows := do
  if keyNames.isEmpty || keyNames.eraseDups.length != keyNames.length ||
      !(keyNames ++ fields).all (fun name => table.columns.any (fun column => column.name == name))
    then none
    else
      let records : ApplicationKeyRows ← (table.project (keyNames ++ fields)).mapM fun (_, cells) => do
        let values ← cells.mapM id
        pure (values.take keyNames.length, values.drop keyNames.length)
      if ApplicationKeyRows.Valid records then some records else none

/-- Observe {name}`projectApplicationRows` from the selected stored table.
An absent table returns {name}`Option.none`, distinct from a present empty
table's {lean}`(some [] : Option ApplicationKeyRows)`. Use an empty protected
field list for keys alone; the key/domain checks remain. -/
def observeApplicationRows (name : String) (keyNames fields : List String)
    (database : Database) : Option ApplicationKeyRows := do
  let table ← database name
  projectApplicationRows table keyNames fields

/-- Require {name}`Conforms` and a defined application-key observation as the
representation invariant. Observe through {name}`observeApplicationRows`.
An absent or invalid-key table cannot satisfy the invariant. Use this helper
for the stated key policy; general {name}`Interpretation` remains available
for other NULL, duplicate and identity policies. -/
def applicationKeyInterpretation (schema : Schema) (name : String)
    (keyNames fields : List String) : Interpretation ApplicationKeyRows where
  invariant database := Conforms schema database ∧
    ∃ records, observeApplicationRows name keyNames fields database = some records
  observe := observeApplicationRows name keyNames fields

/-- A convenience {name}`LogicalContract` requiring valid application keys and
{name}`List.Perm` of complete records on success and failure. Permutation retains
multiplicity and protected cells while allowing reordered rows and changed
physical rowids. Schema and applicability predicates are true for every input;
override them through the general constructor when the application needs more.
Failure position and reason impose no additional condition in this helper. -/
def applicationKeyPreservation : LogicalContract ApplicationKeyRows where
  valid := ApplicationKeyRows.Valid
  change before after := after.Perm before
  schemaRequirement := fun _ => True
  failure before _ _ after := after.Perm before
  applicability := fun _ _ => True

end SqliteVerifier
