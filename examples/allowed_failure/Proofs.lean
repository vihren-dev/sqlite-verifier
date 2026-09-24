import Generated
import SqliteVerifier.FailureDemonstration

/-! A universal proof of the separate approved failure policy. -/
namespace Proofs

/-- The third statement fails; the fourth is skipped and old observations survive. -/
theorem migrationCorrect : Generated.expected :=
  SqliteVerifier.Demonstration.failureMigrationCorrect

end Proofs
