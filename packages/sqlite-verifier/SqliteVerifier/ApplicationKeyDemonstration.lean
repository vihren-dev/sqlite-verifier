import SqliteVerifier.ApplicationKeyPreservation
import SqliteVerifier.Demonstration

set_option doc.verso true

/-! A variant of the invoice example chooses amount as a logical key for this
small engineering case. Admission requires distinct non-NULL amounts; a real
application can select its own business identifier and protected fields. -/

open Belay.Sqlite

namespace SqliteVerifier.ApplicationKeyDemonstration

/-- The invoice table observed by this fixed example; {lean}`"invoices"`. -/
def invoiceTableName : String := "invoices"
/-- The single logical key field; {lean}`["amount"]`. Its observed values must
be distinct and non-NULL. General readers accept another key-name list. -/
def invoiceKeyNames : List String := ["amount"]
/-- The protected old field; {lean}`["amount"]`. This policy retains amounts
as both identity and protected data for the small engineering example. -/
def invoiceProtectedFields : List String := ["amount"]

/-- Require a defined observation keyed by amount, protecting amount itself.
For the given database, some records are returned by {name}`observeApplicationRows`
for the invoice table of {name}`Demonstration.startCatalog` under the named
key/field policy. An absent table or column, missing cell, NULL key or duplicate
key makes this false. An empty table with the requested columns satisfies it. It
asserts no SQL UNIQUE constraint; conformance is separate. -/
def admitted (database : Database) : Prop :=
  ∃ records, observeApplicationRows Demonstration.startCatalog invoiceTableName invoiceKeyNames
    invoiceProtectedFields database = some records

/-- Preserve complete keyed records up to permutation, require the invoice note
catalog entry and require success. Use the general contract for another key/order
policy; failure safety retains the convenience permutation relation. -/
def requirements : LogicalContract ApplicationKeyRows :=
  { applicationKeyPreservation with
    catalogRequirement := Demonstration.requirements.catalogRequirement
    applicability := requiresSuccess }

/-- Observe admitted invoice records under the starting catalog. Physical rowids
are absent and stored order is compared only up to permutation. -/
def current (profile : Profile) : Interpretation ApplicationKeyRows :=
  applicationKeyInterpretation profile Demonstration.startCatalog invoiceTableName invoiceKeyNames
    invoiceProtectedFields

/-- Observe the same keyed records under the resulting catalog, including the note
and independent audit table. The selected old amount remains protected. -/
def next (profile : Profile) : Interpretation ApplicationKeyRows :=
  applicationKeyInterpretation profile Demonstration.nextCatalog invoiceTableName invoiceKeyNames
    invoiceProtectedFields

/-- The complete {name}`VerificationConditions` hold for the fixed schema extension,
{name}`requirements` and this key policy, for every database satisfying
{name}`admitted` and every profile that allows two columns. Nonempty admission
uses the empty invoice table. Before/after representations are sound, schema-only
support holds, and every related outcome succeeds with the required catalog and a
permutation of the original records. {name}`unreachableFailures` selects the
impossible failure representations. The proof reuses the existing success
certificate and the generic extension observation law; it never enumerates or
assumes the stored invoice rows. -/
theorem migrationCorrect (profile : Profile) (columns : 2 ≤ profile.limits.columns) :
    VerificationConditions Demonstration.startCatalog Demonstration.nextCatalog
      Demonstration.script admitted requirements (current profile) (next profile) unreachableFailures profile := by
  have checked := Demonstration.migrationCorrect profile columns
  obtain ⟨startValid, _, _⟩ := Demonstration.catalogs_valid columns
  apply VerificationConditions.of_runSql
  · refine ⟨Demonstration.startCatalog.emptyDatabase,
      Catalog.emptyDatabase_conforms startValid, [], ?_⟩
    decide +kernel
  · simpa [SoundRepresentation, requirements, current] using applicationKeyPreservation_sound profile
      Demonstration.startCatalog invoiceTableName invoiceKeyNames invoiceProtectedFields
  · simpa [SoundRepresentation, requirements, next] using applicationKeyPreservation_sound profile
      Demonstration.nextCatalog invoiceTableName invoiceKeyNames invoiceProtectedFields
  · exact unreachableFailures_sound requirements profile
  · intro database allowed
    exact ⟨allowed.1, allowed.2⟩
  · intro database allowed
    exact checked.ready database ⟨allowed.1, trivial⟩
  · intro database allowed
    have oldAdmission : Admitted profile Demonstration.startCatalog (fun _ => True) database :=
      ⟨allowed.1, trivial⟩
    have originalObligations := checked.outcomes database oldAdmission
      (runSql Demonstration.script database) (ProfileExecutes.of_readsClock (by decide))
    obtain ⟨old, oldRead, _⟩ := (checked.beforeSound database (checked.starting database oldAdmission)).2
    have oldPost := originalObligations.2 old oldRead
    obtain ⟨table, present, shape, valid, _⟩ := Demonstration.admitted_invoices oldAdmission
    have covered : Covers table (invoiceKeyNames ++ invoiceProtectedFields) := by
      intro name member
      simp only [invoiceKeyNames, invoiceProtectedFields, List.mem_append, List.mem_singleton, or_self] at member
      subst name
      exact ⟨0, by rw [shape]; decide +kernel⟩
    have located : tablePosition Demonstration.startCatalog invoiceTableName = some 0 := by decide +kernel
    have growth := runSql_extends
      (script := Demonstration.script) (by simp [SchemaOnly, Demonstration.script]) database
    have preserved := DatabaseExtends.observeApplicationRows growth located present
      (fun row member => (valid.2 row member).2.1) covered
    have sameNames : observeApplicationRows Demonstration.nextCatalog invoiceTableName invoiceKeyNames
        invoiceProtectedFields = observeApplicationRows Demonstration.startCatalog invoiceTableName
          invoiceKeyNames invoiceProtectedFields := by
      have nextLocated : tablePosition Demonstration.nextCatalog invoiceTableName = some 0 := by decide +kernel
      funext database
      simp [observeApplicationRows, located, nextLocated]
    cases result : runSql Demonstration.script database with
    | failure position reason stopped =>
      simpa [result, Demonstration.requirements, requiresSuccess] using originalObligations.1
    | pending persisted visible error =>
      simpa [result, Demonstration.requirements, requiresSuccess] using originalObligations.1
    | success final =>
      rw [result] at oldPost preserved
      refine ⟨trivial, ?_⟩
      intro records beforeRead
      have observed : observeApplicationRows Demonstration.nextCatalog invoiceTableName invoiceKeyNames
          invoiceProtectedFields final = some records := by
        rw [sameNames]
        simpa [current, applicationKeyInterpretation, Outcome.database] using preserved.trans beforeRead
      refine ⟨⟨oldPost.1.1, records, observed⟩, oldPost.2.1, records, observed, ?_⟩
      exact List.Perm.refl records
  · decide

end SqliteVerifier.ApplicationKeyDemonstration
