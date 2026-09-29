"""Shared example cases and paths for the ADR 0003 latency experiments."""

from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
"""Repository root; the experiments use its checkout runtime (`just build`)."""

WORK = ROOT / "build" / "adr-0003-latency"
"""Scratch outputs: compiled examples, exports and the cloned exporter."""


@dataclass(frozen=True)
class ExampleCase:
    """One checked-in example verified with its approved contract and SQLite profile."""

    name: str
    schema: Path
    approved: Path
    candidate: Path
    profile: str
    theorem: str

    def verify_arguments(self) -> list[str]:
        """Public `migration-check verify` arguments for this example."""
        return ["verify", "--profile", self.profile, "--format", "json",
                "--schema", str(self.schema), "--requirements", str(self.approved / "Requirements.lean"),
                "--interpretation", str(self.approved / "Interpretation.lean"),
                "--migration", str(self.candidate / "migration.sql"),
                "--next-interpretation", str(self.candidate / "NextInterpretation.lean"),
                "--proofs", str(self.candidate / "Proofs.lean")]


EXAMPLES = ROOT / "examples"
CASES = (
    ExampleCase("small", EXAMPLES / "approved/schema.sql", EXAMPLES / "approved",
                EXAMPLES / "add_column_then_table", "3.51.0", "Proofs.migrationCorrect"),
    ExampleCase("refutation", EXAMPLES / "approved/schema.sql", EXAMPLES / "approved",
                EXAMPLES / "missing_required_column", "3.51.0", "Proofs.migrationViolated"),
    ExampleCase("atuin", EXAMPLES / "atuin/schema.sql", EXAMPLES / "atuin/approved",
                EXAMPLES / "atuin", "3.46.0", "Proofs.migrationCorrect"),
)
