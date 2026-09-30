"""P1 scenarios: private example copies and the agent edits applied before each trial.

Edits follow ADR 0003's P1 matrix. A proof-only edit changes the proof file's bytes
without changing meaning. A SQL edit changes the migration and whatever candidate
file must follow it. A contract edit changes the approved requirements' bytes, so no
approved stage can be reused.
"""

from dataclasses import dataclass
from pathlib import Path
import shutil

from cases import ROOT

EXAMPLES = ROOT / "examples"
CHANGES = ("proof", "sql", "contract")


@dataclass(frozen=True)
class Scenario:
    """One example: approved and candidate directories, schema, profile and expected status."""

    name: str
    approved: str
    candidate: str
    schema: str
    profile: str
    expected: str


SCENARIOS = (
    Scenario("small", "approved", "add_column_then_table", "approved/schema.sql", "3.51.0", "VERIFIED"),
    Scenario("refutation", "approved", "missing_required_column", "approved/schema.sql", "3.51.0", "VIOLATED"),
    Scenario("atuin", "atuin/approved", "atuin", "atuin/schema.sql", "3.46.0", "VERIFIED"),
)


@dataclass(frozen=True)
class Copy:
    """Private, writable copies of one scenario's inputs."""

    approved: Path
    candidate: Path
    schema: Path
    alternate: Path | None

    def arguments(self, profile: str) -> list[str]:
        """Contract and SQL arguments shared by every command."""
        return ["--profile", profile, "--format", "json", "--schema", str(self.schema),
                "--requirements", str(self.approved / "Requirements.lean"),
                "--interpretation", str(self.approved / "Interpretation.lean"),
                "--migration", str(self.candidate / "migration.sql")]

    def candidate_arguments(self) -> list[str]:
        """Candidate source arguments for `verify` and `prepare`."""
        return ["--next-interpretation", str(self.candidate / "NextInterpretation.lean"),
                "--proofs", str(self.candidate / "Proofs.lean")]


def materialize(scenario: Scenario, directory: Path) -> Copy:
    """Copy the whole examples tree so relative imports and helpers keep working."""
    shutil.rmtree(directory, ignore_errors=True)
    shutil.copytree(EXAMPLES, directory, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
    for path in directory.rglob("*"):
        path.chmod(0o755 if path.is_dir() else 0o644)
    alternate = directory / "table_then_column" if scenario.name == "small" else None
    return Copy(directory / scenario.approved, directory / scenario.candidate, directory / scenario.schema, alternate)


def replace(path: Path, old: str, new: str) -> None:
    """Apply one required textual edit."""
    text = path.read_text()
    if old not in text:
        raise ValueError(f"edit target missing in {path}: {old!r}")
    path.write_text(text.replace(old, new, 1))


def apply_edit(scenario: Scenario, copy: Copy, change: str, trial: int) -> None:
    """Apply the agent's edit for this trial; every trial produces new bytes."""
    if change == "proof":
        with (copy.candidate / "Proofs.lean").open("a") as stream:
            stream.write(f"\n-- agent edit {trial}\n")
    elif change == "contract":
        with (copy.approved / "Requirements.lean").open("a") as stream:
            stream.write(f"\n-- approved edit {trial}\n")
    elif scenario.name == "small":
        # The proof is tied to the exact script, so alternate between the two valid orders.
        assert copy.alternate is not None
        for name in ("migration.sql", "NextInterpretation.lean", "Proofs.lean"):
            first, second = copy.candidate / name, copy.alternate / name
            contents = first.read_bytes()
            first.write_bytes(second.read_bytes())
            second.write_bytes(contents)
    elif scenario.name == "refutation":
        migration = copy.candidate / "migration.sql"
        text = migration.read_text()
        start = text.index("CREATE TABLE audit(") + len("CREATE TABLE audit(")
        migration.write_text(text[:start] + f"entry{trial}" + text[text.index(" TEXT);", start):])
    else:
        previous = f"field{trial - 1}" if trial > 0 else "shell"
        replace(copy.candidate / "migration.sql", f"add column {previous} text;", f"add column field{trial} text;")
        replace(copy.candidate / "AtuinFacts.lean", f'name := "{previous}"', f'name := "field{trial}"')
