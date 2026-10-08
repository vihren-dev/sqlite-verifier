import Generated
import SqliteVerifier.ApplicationKeyDemonstration

set_option doc.verso true

/-! The candidate uses the complete library certificate only after the generated
target binds this candidate's exact SQL and the approved representation policy. -/

namespace Proofs

/-- The exact generated verification target holds for every admitted starting
database under the stated key policy. The public certificate supplies all fields;
the generated target binds the authored SQL, schemas and representation sources. -/
theorem migrationCorrect : Generated.expected :=
  SqliteVerifier.ApplicationKeyDemonstration.migrationCorrect

end Proofs
