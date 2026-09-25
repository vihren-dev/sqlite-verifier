"""Report independent proof, syntax, fixture and concrete semantic evidence with explicit limits."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys

from coverage_catalog import CLAIMS, EXCLUSIONS, THEOREMS
from coverage_evidence import command, proof_probe, structured
from coverage_atuin import sql_report
from import_fixture import fixture
from model_cases import cases

ROOT = Path(__file__).resolve().parents[1]


def grammar_inventory(root: Path, version: str, directory: str, exported: dict[str, object],
                      regression: dict[str, object]) -> dict[str, object]:
    """Count each independently generated grammar without claiming executed-rule coverage."""
    try:
        generated = sum("::=" in line for line in (root / directory / "syntax.y").read_text().splitlines())
    except OSError:
        generated = None
    upstream_count = (sum("::=" in line for line in str(exported["stdout"]).splitlines())
                      if exported["status"] == "PASSED" else None)
    if generated is None or generated == 0 or generated != upstream_count:
        exported.update(status="FAILED", diagnostic="Generated/default grammar inventories unavailable or differ")
    smoke = re.search(re.escape(version) + r" parser checks passed: (\d+) grammar scripts",
                      str(regression.get("stdout", "")))
    if regression["status"] == "PASSED" and smoke is None:
        regression.update(status="FAILED", diagnostic=f"{version} parser script denominator missing")
    return {"generated_productions": generated, "upstream_default_productions": upstream_count,
            "inventory_is_equivalence_proof": False, "production_execution_coverage": "NOT_INSTRUMENTED",
            "regression_scripts": int(smoke[1]) if smoke else None,
            "regression_scope": "authored smoke scripts, not production or semantic coverage"}


def collect(root: Path, native: str) -> dict[str, object]:
    """Refresh existing evidence; an unavailable comparison is never reported as a match."""
    checks = {
        "proof_build": command(["lake", "build", "SqliteVerifier"], root, 60),
        "parser_regressions": command([sys.executable, "tests/parser_test.py"], root, 30),
        "upstream_native": command([sys.executable, "tests/conformance_native_test.py", native], root, 20),
        "derived_native_model": command([sys.executable, "tests/conformance_model_test.py", native], root, 180),
        "atuin_sql": command([sys.executable, "tests/atuin_sql_test.py"], root, 30),
        "grammar_export": command([str(root / "build/parser/lemon"), "-g",
                                   str(root / "parser/upstream/parse.y")], root, 5),
        "grammar_346_export": command([str(root / "build/parser-3.46.0/lemon"), "-g",
                                       str(root / "parser/upstream-3.46.0/parse.y")], root, 5),
    }
    checks["named_proofs"] = (proof_probe(root) if checks["proof_build"]["status"] == "PASSED"
                              else {"status": "NOT_RUN", "diagnostic": "Library build failed"})
    upstream = structured(checks["upstream_native"])
    derived = structured(checks["derived_native_model"])
    imported = fixture()
    upstream_complete = (isinstance(upstream, dict) and isinstance(upstream.get("cases"), list)
                         and len(upstream["cases"]) == imported["coverage"]["selected_call_instances"]
                         and all(isinstance(row, dict) and isinstance(row.get("upstream_id"), str)
                                 and isinstance(row.get("occurrence"), int)
                                 and row.get("native_status") == "MATCHES_UPSTREAM"
                                 and row.get("grammar_status") == "PARSED" for row in upstream["cases"])
                         and {(row["upstream_id"], row["occurrence"]) for row in upstream["cases"]}
                         == {(row["upstream_id"], row["occurrence"]) for row in imported["cases"]})
    if checks["upstream_native"]["status"] == "PASSED" and not upstream_complete:
        checks["upstream_native"].update(status="FAILED", diagnostic="Incomplete upstream comparison report")
    authored = cases()
    expected_names = {case.name for case in authored}
    denominator = len(authored)
    complete = (len(expected_names) == denominator and isinstance(derived, list) and len(derived) == denominator and all(
        isinstance(row, dict) and isinstance(row.get("case"), str)
        and row.get("native_status") == "MATCHES_INDEPENDENT_EXPECTATION"
        and row.get("grammar_status") == "PARSED"
        and row.get("translation_status") == "PRODUCTION_PIPELINE"
        and row.get("model_status") == "KERNEL_CHECKED_CONCRETE_ASSERTIONS" for row in derived)
        and {row["case"] for row in derived} == expected_names)
    if checks["derived_native_model"]["status"] == "PASSED" and not complete:
        checks["derived_native_model"].update(status="FAILED", diagnostic="Incomplete concrete comparison report")
    grammar = grammar_inventory(root, "3.51.0", "build/parser", checks["grammar_export"], checks["parser_regressions"])
    grammar346 = grammar_inventory(root, "3.46.0", "build/parser-3.46.0", checks["grammar_346_export"], checks["parser_regressions"])
    atuin = sql_report(root, checks["atuin_sql"])
    return {
        "report_version": 1, "profile": "3.51.0",
        "status": "EVIDENCE_CHECKS_PASSED" if all(row["status"] == "PASSED" for row in checks.values()) else "EVIDENCE_CHECKS_FAILED",
        "proofs": {"scope": list(THEOREMS), "denominator": len(THEOREMS),
                   "unit": "explicitly catalogued model theorems; not all library declarations",
                   "status": checks["named_proofs"]["status"], "product_gate": "NOT_RUN_BY_THIS_REPORT"},
        "grammar": grammar, "additional_grammars": {"3.46.0": grammar346},
        "atuin_sql": atuin,
        "documented_claims": {"catalogued_entries": len(CLAIMS), "upstream_requirement_ids": 3,
                              "sqlite_documentation_total": None, "entries": CLAIMS,
                              "status": "TRACEABILITY_INVENTORY_NOT_PROOF_COMPLETION"},
        "upstream_fixtures": {**imported["coverage"], "unit": "textual alter3.test calls, not expanded Tcl executions",
                              "native_evidence": upstream, "model_status": "NOT_YET_MODEL_CHECKED",
                              "exclusion": "inherited view v1 and unmodeled statements retained"},
        "semantic_support": {"modeled_statement_forms": ["ordinary CREATE TABLE", "nullable ALTER TABLE ADD COLUMN"],
                             "all_sqlite_statement_forms": None, "scope": "docs/semantic-subset.md",
                             "execution_profile": "docs/execution-profile.md"},
        "native_model": {"authored_case_denominator": denominator,
                         "completed_matching_cases": denominator if complete else None,
                         "observed_discrepancies": 0 if complete else None,
                         "failed_check_meaning": "Failure may be a mismatch or unavailable evidence; inspect diagnostics",
                         "universal_native_refinement": "NOT_PROVED", "cases": derived},
        "exclusions": EXCLUSIONS, "checks": checks,
    }


def main() -> int:
    """Write the report even when a bounded check fails, and fail the shared check accordingly."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    try:
        report = collect(ROOT, os.environ.get("SQLITE3") or shutil.which("sqlite3") or "sqlite3")
    except (OSError, ValueError) as error:
        report = {"report_version": 1, "status": "EVIDENCE_CHECKS_FAILED",
                  "diagnostic": str(error), "exclusions": EXCLUSIONS}
    rendered = json.dumps(report, indent=2) + "\n"
    if options.output:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(rendered)
        print(f"{report['status']}: {options.output}")
    else:
        print(rendered, end="")
    return 0 if report["status"] == "EVIDENCE_CHECKS_PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
