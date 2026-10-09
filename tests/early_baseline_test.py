"""Independently selected early approval failures and sealed-snapshot acceptance."""

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from migration_check.baseline import check_baseline
from migration_check.cli import verify
from migration_check.compile import compile_modules
from migration_check.diagnostics import Rejection
from tests.source_fixtures import (BaselineFixture, baseline_case, invalid_baseline_case,
                                   source_runtime_only)

pytestmark = [pytest.mark.integration, pytest.mark.approval, pytest.mark.requires_lean,
              pytest.mark.requires_native("parser-library")]


def assert_drift(case: BaselineFixture, expected: str) -> None:
    """Protected drift must report INPUT_ERROR before the deliberately invalid proof can compile."""
    with patch("migration_check.compile.compile_modules") as compile_spy:
        with pytest.raises(Rejection) as rejected:
            verify(case.options)
        assert rejected.value.diagnostic()["status"] == "INPUT_ERROR", rejected.value
        assert expected in str(rejected.value), rejected.value
        compile_spy.assert_not_called()


def test_changed_transitive_source(invalid_baseline_case: BaselineFixture) -> None:
    """Changing a transitive approved dependency takes precedence over an invalid candidate proof."""
    case = invalid_baseline_case
    deeper = case.approved / "Deeper.lean"
    deeper.write_bytes(case.original[deeper] + b"-- unapproved change\n")
    assert_drift(case, "approved/Deeper.lean")


def test_added_closure_member(invalid_baseline_case: BaselineFixture) -> None:
    """A dependency newly present in the actual closure rejects even when all known bytes match."""
    case = invalid_baseline_case
    case.baseline.write_text(json.dumps({key: value for key, value in case.hashes.items()
                                        if key != "approved/Deeper.lean"}))
    assert_drift(case, "approved/Deeper.lean")


def test_removed_closure_member(invalid_baseline_case: BaselineFixture) -> None:
    """A previously approved member missing from the actual closure cannot disappear silently."""
    case = invalid_baseline_case
    case.baseline.write_text(json.dumps({**case.hashes, "approved/Removed.lean": "a" * 64}))
    assert_drift(case, "approved/Removed.lean")


def test_changed_schema_pin(invalid_baseline_case: BaselineFixture) -> None:
    """A changed optional starting-schema pin rejects before any proof compilation."""
    case = invalid_baseline_case
    case.baseline.write_text(json.dumps({**case.hashes, "schema.sql": "a" * 64}))
    assert_drift(case, "schema.sql")


def test_malformed_schema_pin(invalid_baseline_case: BaselineFixture) -> None:
    """A malformed schema digest remains an input error despite an independently invalid proof."""
    case = invalid_baseline_case
    case.baseline.write_text(json.dumps({**case.hashes, "schema.sql": "bad"}))
    assert_drift(case, "Invalid approved baseline hash")


def test_missing_dependency_precedence(invalid_baseline_case: BaselineFixture) -> None:
    """An unresolved import is diagnosed before even a malformed approved baseline can be compared."""
    case = invalid_baseline_case
    case.baseline.write_text(json.dumps({**case.hashes, "schema.sql": "bad"}))
    (case.approved / "Helper.lean").write_text("import MissingDependency\n")
    with patch("migration_check.compile.compile_modules") as compile_spy:
        with pytest.raises(ValueError, match="Missing or conflicting"):
            verify(case.options)
        compile_spy.assert_not_called()


def test_optional_schema_pin_and_sealed_snapshot(baseline_case: BaselineFixture) -> None:
    """Unpinned equivalent schema and approved source snapshots still compile and independently verify."""
    case = baseline_case
    case.baseline.write_text(json.dumps(case.hashes))
    schema = case.approved / "schema.sql"
    schema.write_bytes(schema.read_bytes() + b"\n-- equivalent unpinned schema\n")
    proof = case.candidate / "Proofs.lean"

    def check_then_mutate(path: Path, actual: dict[str, str]) -> None:
        """Changing every original source after approval cannot change the sealed compiler inputs."""
        check_baseline(path, actual)
        for source in (*case.original, proof):
            source.write_text("def invalidAfterSnapshot : Nat := false\n")
        schema.write_text("not SQL\n")

    with patch("migration_check.compile.check_baseline", check_then_mutate), \
            patch("migration_check.compile.compile_modules", wraps=compile_modules) as compile_spy:
        report = verify(case.options)
        assert report["status"] == "VERIFIED", report
        assert compile_spy.called, "matching snapshots skipped compilation"
        assert isinstance(report["inputs"], dict)
        for name, digest in case.hashes.items():
            assert report["inputs"][name] == digest
