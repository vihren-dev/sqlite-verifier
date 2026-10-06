import SchemaInputs
import Requirements

set_option doc.verso true

/-! Approved invoice meaning uses the sealed translation of the starting SQL.
Its protected baseline binds both this source and the authored schema bytes. -/
namespace Interpretation

/-- For every database, the approved condition is true. It adds no restriction;
{name}`SqliteVerifier.Admitted` still requires conformance to the starting schema. -/
def admitted (_ : SqliteVerifier.Database) : Prop := True

/-- Read every invoice's physical identity and amount from actual storage. The
invariant requires conformance to {name}`Generated.startSchema` and coverage of
amount; a missing invoice table produces no observation. The starting schema is
supplied only by sealed {lit}`SchemaInputs`, so no handwritten duplicate is needed. -/
def current : SqliteVerifier.Interpretation Requirements.LogicalState :=
  SqliteVerifier.projectedInterpretation Generated.startSchema "invoices" ["amount"]

end Interpretation
