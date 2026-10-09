import SqliteVerifier.ApplicationKeys

set_option doc.verso true

open Belay.Sqlite

namespace SqliteVerifier

/-! Soundness and extension laws let application-key users reuse schema proofs
while keeping their own logical contract and comparison policy. -/

/-- For every table, requested key/field lists and returned records, a successful
{name}`projectApplicationRows` read implies {name}`ApplicationKeyRows.Valid`.
An absent read cannot meet the premise; no {name}`Table.Valid` assumption is
required. Use this for the convenience contract's logical validity.
The proof follows the optional decode and its explicit key-validity check. -/
theorem projectApplicationRows_valid
    (read : projectApplicationRows table keyNames fields = some records) :
    ApplicationKeyRows.Valid records := by
  unfold projectApplicationRows at read
  split at read
  · simp at read
  · obtain ⟨decoded, _, read⟩ := Option.bind_eq_some_iff.mp read
    split at read
    · simp_all
    · simp_all

/-- For every database, table name, key/field lists and returned records, a
successful {name}`observeApplicationRows` read implies valid logical keys.
An absent table or refused read cannot satisfy the premise. No conformance
assumption is needed. The proof applies the projection result to the stored table. -/
theorem observeApplicationRows_valid
    (read : observeApplicationRows name keyNames fields database = some records) :
    ApplicationKeyRows.Valid records := by
  cases stored : database name with
  | none => simp [observeApplicationRows, stored] at read
  | some table =>
    exact projectApplicationRows_valid (by simpa [observeApplicationRows, stored] using read)

/-- For every contract, schema, table name and requested key/field lists,
assume each successful projection of every valid table satisfies the contract's
logical validity. Then {name}`applicationKeyInterpretation` is a
{name}`SoundRepresentation`: every database satisfying its invariant conforms
to the schema and has a defined observation satisfying {name}`LogicalContract.valid`.
An impossible invariant leaves those database obligations vacuous; an empty
table still needs the validity premise for its empty record list.
Use this with application-specific contracts.
The proof extracts the stored valid table from whole-shape conformance and applies the premise. -/
theorem applicationKeyInterpretation_sound (contract : LogicalContract ApplicationKeyRows)
    (schema : Schema) (name : String) (keyNames fields : List String)
    (valid : ∀ table, table.Valid → ∀ records,
      projectApplicationRows table keyNames fields = some records → contract.valid records) :
    SoundRepresentation contract schema (applicationKeyInterpretation schema name keyNames fields) := by
  intro database invariant
  obtain ⟨conforms, records, read⟩ := invariant
  refine ⟨conforms, records, read, ?_⟩
  cases stored : database name with
  | none => simp [observeApplicationRows, stored] at read
  | some table =>
    exact valid table ((conforms.2 name).2 table stored) records
      (by simpa [observeApplicationRows, stored] using read)

/-- For every schema, table name and key/field lists, the application-key
interpretation is a {name}`SoundRepresentation` for {name}`applicationKeyPreservation`:
every database satisfying its invariant conforms to the schema and has a
defined observation satisfying {name}`ApplicationKeyRows.Valid`, with distinct,
nonempty key tuples containing no NULL. No extra contract-validity premise is
needed because every defined read has valid keys. An impossible invariant
leaves its database obligations vacuous.
The proof uses the general soundness theorem and projection validity. -/
theorem applicationKeyPreservation_sound (schema : Schema) (name : String)
    (keyNames fields : List String) :
    SoundRepresentation applicationKeyPreservation schema
      (applicationKeyInterpretation schema name keyNames fields) := by
  apply applicationKeyInterpretation_sound
  intro table _ records read
  exact projectApplicationRows_valid read

/-- For every table and name list, {name}`Covers` implies that all requested
names occur in its columns. An empty list satisfies both conditions vacuously.
Use this to establish the reader's metadata check. The proof converts each
successful first-index lookup into its Boolean existence test. -/
theorem Covers.columnsPresent (covered : Covers table names) :
    names.all (fun name => table.shape.columns.any (fun column => column.name == name)) = true := by
  apply List.all_eq_true.mpr
  intro name member
  obtain ⟨index, found⟩ := covered name member
  simp [← List.findIdx?_isSome, found]

/-- For every before/after table and requested key/field lists, assume
{name}`TableExtends`, correct old row widths, and coverage of every requested
name in the old table. Then {name}`projectApplicationRows` is unchanged,
including refusal for an invalid key. With no old rows width is vacuous;
coverage still requires the named columns. Use this for schema extensions.
The proof preserves metadata presence and rewrites the complete cell projection. -/
theorem TableExtends.projectApplicationRows (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length)
    (covered : Covers before (keyNames ++ fields)) :
    projectApplicationRows after keyNames fields = projectApplicationRows before keyNames fields := by
  have oldColumns := SqliteVerifier.Covers.columnsPresent covered
  have newColumns := SqliteVerifier.Covers.columnsPresent (extension.covers covered)
  simp only [SqliteVerifier.projectApplicationRows, oldColumns, newColumns, Bool.not_true, Bool.or_false]
  rw [extension.project width covered]

/-- For every before/after database, stored old table, selected name and requested
key/field lists, assume {name}`DatabaseExtends`, the old table's presence,
correct old row widths and old coverage of every requested name. Then
{name}`observeApplicationRows` at that name is unchanged, including an absent
read caused by invalid keys. An absent old table cannot satisfy the premise;
with no old rows only widths are vacuous. Use this for existing-table observations.
The proof selects the retained table and applies its projection extension law. -/
theorem DatabaseExtends.observeApplicationRows (extension : DatabaseExtends before after)
    (present : before name = some table)
    (width : ∀ row ∈ table.rows, row.values.length = table.shape.columns.length)
    (covered : Covers table (keyNames ++ fields)) :
    SqliteVerifier.observeApplicationRows name keyNames fields after =
      SqliteVerifier.observeApplicationRows name keyNames fields before := by
  obtain ⟨replacement, stored, extended⟩ := extension name table present
  simp only [SqliteVerifier.observeApplicationRows, present, stored]
  exact SqliteVerifier.TableExtends.projectApplicationRows extended width covered

end SqliteVerifier
