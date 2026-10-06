"""Export actual private fixtures and submit retained hostile data to the bundle checker."""

from dataclasses import dataclass
import json
import os
from pathlib import Path

import pytest

from migration_check.import_path import merged_search_path
from migration_check.prepare import EXPORT_ROOTS, PROTECTED_BASE_MODULE
from tests.kernel_fixture import KernelCase
from tests.runtime_support import CommandResult


@dataclass
class BundleCase:
    """Use the same protected compiled inputs as the old gate, with candidate data as NDJSON."""

    kernel: KernelCase
    exporter: Path
    checker: Path
    generated: Path

    def export(self) -> Path:
        """Retain the actual pinned export, including its raw metadata and table records."""
        case = self.kernel
        roots = (case.sysroot / "lib/lean", case.library, case.root / "trusted", case.root / "candidate")
        with merged_search_path(roots, case.root) as paths:
            environment = {**case.environment, "LEAN_PATH": os.pathsep.join(map(str, paths))}
            trusted_imports = {PROTECTED_BASE_MODULE}
            # These fixture modules are compiled by the verifier; their definitions stay protected.
            omitted = {"SchemaInputs", "Requirements", "Interpretation", "SqlInputs"} | trusted_imports
            result = case.runner([str(self.exporter), *["--omit=" + module for module in sorted(omitted)],
                "--ignore-missing", "Proofs", "--", *EXPORT_ROOTS],
                cwd=case.root, environment=environment, timeout=30)
        assert result.returncode == 0, result.diagnostic()
        bundle = case.root / "bundle.ndjson"
        bundle.write_text(json.dumps({"bundle": 1, "trusted_imports": sorted(trusted_imports)}) + "\n" + result.stdout)
        return bundle

    def check(self, bundle: Path, *, environment: dict[str, str] | None = None,
              library: str | None = None) -> CommandResult:
        """Run only the checker on retained data, with the same 60-second test deadline."""
        case = self.kernel
        result = case.runner([str(self.checker), library or str(case.library),
                              str(case.root / "trusted"), str(bundle), str(self.generated)],
                             cwd=case.root, timeout=60,
                             environment=case.environment if environment is None else environment)
        assert "CANDIDATE_INITIALIZER_RAN" not in result.stdout + result.stderr, result.diagnostic()
        return result


@pytest.fixture
def bundle_case(kernel: KernelCase, runtime_root: Path) -> BundleCase:
    """Bind the exact structural request to the empty-schema, no-op kernel fixture."""
    generated = kernel.root / "generated.json"
    generated.write_text(json.dumps({"version": 1, "profile": "sqlite351", "schema": [],
                                     "nextSchema": [], "script": []}))
    return BundleCase(kernel, runtime_root / ".lake/build/bin/migration-proof-exporter",
                      runtime_root / ".lake/build/bin/migration-bundle-checker", generated)
