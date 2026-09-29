"""`verify` with an opt-in stage store: same results, fresh fallback, approved closures excluded."""

from collections.abc import Callable
import os
from pathlib import Path

import pytest

from migration_check.stage_store import MEASUREMENT_APPROVED_VARIABLE, STORE_VARIABLE
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.approval, pytest.mark.requires_lean, pytest.mark.requires_native]


@pytest.fixture
def verify(runtime_root: Path, example_factory: Callable[[str], Path], tmp_path: Path,
           command_runner: Callable[..., CommandResult]) -> Callable[..., str]:
    """Verify the small positive example with a given store configuration and return the status."""
    examples = example_factory(".")

    def run(store: Path, *, approved_override: bool = False, migration: str = "add_column_then_table") -> str:
        """Run the public entrypoint once; the status must agree with the process exit code."""
        environment = {**os.environ, STORE_VARIABLE: str(store)}
        environment.pop(MEASUREMENT_APPROVED_VARIABLE, None)
        if approved_override:
            environment[MEASUREMENT_APPROVED_VARIABLE] = "1"
        candidate = examples / migration
        result = command_runner([str(runtime_root / "bin/migration-check"), "verify", "--profile", "3.51.0",
                                 "--format", "json", "--schema", str(examples / "approved/schema.sql"),
                                 "--requirements", str(examples / "approved/Requirements.lean"),
                                 "--interpretation", str(examples / "approved/Interpretation.lean"),
                                 "--migration", str(candidate / "migration.sql"),
                                 "--next-interpretation", str(candidate / "NextInterpretation.lean"),
                                 "--proofs", str(candidate / "Proofs.lean")],
                                cwd=tmp_path, timeout=120, environment=environment)
        status = str(result.json_object()["status"])
        assert result.returncode == (0 if status == "VERIFIED" else 1), result.diagnostic()
        return status
    return run


def entries(store: Path) -> set[str]:
    """Published stage entries, ignoring in-progress staging directories."""
    return {path.name for path in store.iterdir() if not path.name.startswith(".")} if store.exists() else set()


def test_generated_stages_reused_approved_compiled_fresh(verify: Callable[..., str], tmp_path: Path) -> None:
    """Only the two generated stages are stored; a second run reuses them with the same result."""
    store = tmp_path / "store"
    assert verify(store) == "VERIFIED"
    first = entries(store)
    assert len(first) == 2, first
    assert verify(store) == "VERIFIED"
    assert entries(store) == first


def test_changed_sql_stores_new_stage(verify: Callable[..., str], tmp_path: Path) -> None:
    """A different migration produces a different SQL stage key and still verifies."""
    store = tmp_path / "store"
    assert verify(store) == "VERIFIED"
    assert verify(store, migration="table_then_column") == "VERIFIED"
    assert len(entries(store)) == 3


def test_damaged_entry_falls_back_to_compilation(verify: Callable[..., str], tmp_path: Path) -> None:
    """A tampered stored artifact is ignored rather than trusted."""
    store = tmp_path / "store"
    assert verify(store) == "VERIFIED"
    for path in store.rglob("*.olean"):
        path.chmod(0o644)
        path.write_bytes(b"not an olean")
    assert verify(store) == "VERIFIED"


def test_measurement_override_stores_approved_stage(verify: Callable[..., str], tmp_path: Path) -> None:
    """The P1 measurement-only override additionally stores and reuses the approved stage."""
    store = tmp_path / "store"
    assert verify(store, approved_override=True) == "VERIFIED"
    assert len(entries(store)) == 3
    assert verify(store, approved_override=True) == "VERIFIED"
