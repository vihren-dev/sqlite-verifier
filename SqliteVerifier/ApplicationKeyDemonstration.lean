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
under the named table/key/field policy. An absent table or column, missing cell,
NULL key or duplicate key makes this false. An empty table with the requested
columns satisfies it. It asserts no SQL UNIQUE constraint; conformance is separate. -/
def admitted (database : Database) : Prop :=
  ∃ records, observeApplicationRows invoiceTableName invoiceKeyNames invoiceProtectedFields database = some records

/-- Preserve complete keyed records up to permutation, require the invoice note
schema and require success. Use the general contract for another key/order policy;
failure safety retains the convenience permutation relation. -/
def requirements : LogicalContract ApplicationKeyRows :=
  { applicationKeyPreservation with
    schemaRequirement := Demonstration.requirements.schemaRequirement
    applicability := requiresSuccess }

/-- Observe admitted invoice records under the starting schema. Physical rowids
are absent and stored order is compared only up to permutation. -/
def current : Interpretation ApplicationKeyRows :=
  applicationKeyInterpretation Demonstration.startSchema invoiceTableName invoiceKeyNames invoiceProtectedFields

/-- Observe the same keyed records under the proposed schema, including the note
and independent audit table. The selected old amount remains protected. -/
def next : Interpretation ApplicationKeyRows :=
  applicationKeyInterpretation Demonstration.nextSchema invoiceTableName invoiceKeyNames invoiceProtectedFields

/-- The complete {name}`VerificationConditions` hold for the fixed schema extension,
{name}`requirements` and this key policy, for every database satisfying {name}`admitted`.
Nonempty admission uses the
empty invoice table. Before/after representations are sound, schema-only support
holds, and every related outcome succeeds with the required schema and a
permutation of the original records. {name}`unreachableFailures` selects the
impossible failure representations.
The proof reuses the existing success certificate and the generic extension
observation law; it never enumerates or assumes the stored invoice rows. -/
theorem migrationCorrect :
    VerificationConditions Demonstration.startSchema Demonstration.nextSchema
      Demonstration.script admitted requirements current next unreachableFailures := by
  apply VerificationConditions.of_runSql
  · refine ⟨Demonstration.startSchema.emptyDatabase,
      Demonstration.startSchema.emptyDatabase_conforms Demonstration.start_valid, [] , ?_⟩
    rfl
  · simpa [SoundRepresentation, requirements, current] using
      applicationKeyPreservation_sound Demonstration.startSchema invoiceTableName invoiceKeyNames invoiceProtectedFields
  · simpa [SoundRepresentation, requirements, next] using
      applicationKeyPreservation_sound Demonstration.nextSchema invoiceTableName invoiceKeyNames invoiceProtectedFields
  · exact unreachableFailures_sound requirements
  · intro database allowed
    exact ⟨allowed.1, allowed.2⟩
  · intro database allowed
    exact Demonstration.migrationCorrect.ready database ⟨allowed.1, trivial⟩
  · intro database allowed
    have oldAdmission : Admitted Demonstration.startSchema (fun _ => True) database :=
      ⟨allowed.1, trivial⟩
    have originalObligations := Demonstration.migrationCorrect.outcomes database oldAdmission
      (runSql Demonstration.script database) .evaluated
    obtain ⟨old, oldRead, _⟩ :=
      (Demonstration.migrationCorrect.beforeSound database
        (Demonstration.migrationCorrect.starting database oldAdmission)).2
    have oldPost := originalObligations.2 old oldRead
    obtain ⟨table, present, columns, valid⟩ := allowed.1.table (name := invoiceTableName) (by rfl)
    have covered : Covers table (invoiceKeyNames ++ invoiceProtectedFields) := by
      intro name member
      simp only [invoiceKeyNames, invoiceProtectedFields, List.mem_append, List.mem_singleton, or_self] at member
      subst name
      exact ⟨0, by simp [columns, Demonstration.amount]⟩
    have growth := runSql_extends
      (script := Demonstration.script) (by simp [SchemaOnly, Demonstration.script]) database
    have preserved := DatabaseExtends.observeApplicationRows growth present
      (fun row member => (valid.2.2 row member).2) covered
    cases result : runSql Demonstration.script database with
    | failure position reason stopped =>
      simpa [result, Demonstration.requirements, requiresSuccess] using originalObligations.1
    | pending persisted visible error =>
      simpa [result, Demonstration.requirements, requiresSuccess] using originalObligations.1
    | success final =>
      rw [result] at oldPost preserved
      refine ⟨trivial, ?_⟩
      intro records beforeRead
      have observed : observeApplicationRows invoiceTableName invoiceKeyNames invoiceProtectedFields final = some records := by
        simpa [current, applicationKeyInterpretation, Outcome.database] using preserved.trans beforeRead
      refine ⟨⟨oldPost.1.1, records, observed⟩, oldPost.2.1, records, observed, ?_⟩
      exact List.Perm.refl records

end SqliteVerifier.ApplicationKeyDemonstration
