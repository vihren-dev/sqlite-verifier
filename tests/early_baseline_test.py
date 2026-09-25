"""Bounded real-runtime checks for approval before compilation of sealed closures."""

import hashlib
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
from time import monotonic
from unittest.mock import patch

from migration_check.baseline import check_baseline
from migration_check.cli import arguments, verify
from migration_check.compile import compile_modules
from migration_check.diagnostics import Rejection

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    """Check drift precedence, closure membership, optional pins and snapshot integrity."""
    started = monotonic()
    with TemporaryDirectory(prefix="early-baseline-test-") as temporary:
        root = Path(temporary)
        approved, candidate = root / "approved", root / "candidate"
        shutil.copytree(ROOT / "examples/approved", approved)
        shutil.copytree(ROOT / "examples/add_column_then_table", candidate)
        requirements = approved / "Requirements.lean"
        requirements.write_text("import Helper\n" + requirements.read_text())
        helper, deeper = approved / "Helper.lean", approved / "Deeper.lean"
        helper.write_text("import Deeper\n")
        deeper.write_text("def approvedVersion : Nat := 1\n")
        original = {path: path.read_bytes() for path in approved.glob("*.lean")}
        hashes = {f"approved/{path.name}": hashlib.sha256(contents).hexdigest()
                  for path, contents in original.items()}
        schema = approved / "schema.sql"
        schema_hash = hashlib.sha256(schema.read_bytes()).hexdigest()
        baseline = root / "baseline.json"
        baseline.write_text(json.dumps({**hashes, "schema.sql": schema_hash}))
        values = ["verify", "--profile", "3.51.0", "--approved-baseline", str(baseline)]
        for name, path in {"schema": schema, "migration": candidate / "migration.sql",
                "requirements": requirements, "interpretation": approved / "Interpretation.lean",
                "next-interpretation": candidate / "NextInterpretation.lean",
                "proofs": candidate / "Proofs.lean"}.items():
            values.extend(["--" + name, str(path)])
        options = arguments(values)
        proof = candidate / "Proofs.lean"
        original_proof = proof.read_bytes()
        proof.write_bytes(original_proof + b"\ndef invalidProof : Nat := false\n")

        def rejected(expected: str) -> None:
            """An invalid proof must not mask protected drift or trigger compilation."""
            with patch("migration_check.compile.compile_modules") as compile_spy:
                try:
                    verify(options)
                except Rejection as error:
                    assert error.diagnostic()["status"] == "INPUT_ERROR", error
                    assert expected in str(error), error
                else:
                    raise AssertionError("protected input drift was accepted")
                compile_spy.assert_not_called()

        deeper.write_bytes(original[deeper] + b"-- unapproved change\n")
        rejected("approved/Deeper.lean")
        deeper.write_bytes(original[deeper])
        # Added/removed members are compared even when remaining source bytes match.
        baseline.write_text(json.dumps({key: value for key, value in hashes.items()
                                        if key != "approved/Deeper.lean"}))
        rejected("approved/Deeper.lean")
        baseline.write_text(json.dumps({**hashes, "approved/Removed.lean": "a" * 64}))
        rejected("approved/Removed.lean")
        baseline.write_text(json.dumps({**hashes, "schema.sql": "a" * 64}))
        rejected("schema.sql")
        baseline.write_text(json.dumps({**hashes, "schema.sql": "bad"}))
        rejected("Invalid approved baseline hash")
        # A missing dependency still fails before baseline comparison.
        helper.write_text("import MissingDependency\n")
        with patch("migration_check.compile.compile_modules") as compile_spy:
            try:
                verify(options)
            except ValueError as error:
                assert "Missing or conflicting" in str(error), error
            else:
                raise AssertionError("invalid import closure reached baseline comparison")
            compile_spy.assert_not_called()
        helper.write_bytes(original[helper])
        proof.write_bytes(original_proof)
        baseline.write_text(json.dumps(hashes))  # Optional schema pin remains optional.
        schema.write_bytes(schema.read_bytes() + b"\n-- equivalent unpinned schema\n")

        def check_then_mutate(path: Path, actual: dict[str, str]) -> None:
            """Changing original files after approval must not change compiler inputs."""
            check_baseline(path, actual)
            for source in (*original, proof):
                source.write_text("def invalidAfterSnapshot : Nat := false\n")
            schema.write_text("not SQL\n")

        with patch("migration_check.compile.check_baseline", check_then_mutate), \
                patch("migration_check.compile.compile_modules", wraps=compile_modules) as compile_spy:
            report = verify(options)
            assert report["status"] == "VERIFIED", report
            assert compile_spy.called, "matching snapshots skipped compilation"
            assert isinstance(report["inputs"], dict)
            for name, digest in hashes.items():
                assert report["inputs"][name] == digest
        # Ordinary no-baseline verification is exercised by cli_test.py.
    print(f"Early baseline: drift, precedence, transitive closure, optional pins, sealed snapshots "
          f"and independent gate passed in {monotonic() - started:.2f}s")


if __name__ == "__main__":
    main()
