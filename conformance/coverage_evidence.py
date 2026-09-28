"""Run bounded evidence commands and preserve errors without manufacturing a passing result."""

import json
import re

from coverage_catalog import THEOREMS


def structured(evidence: dict[str, object]) -> object:
    """Parse runner output only after success; bad output cannot count as zero discrepancies."""
    if evidence["status"] != "PASSED":
        return None
    try:
        value = json.loads(str(evidence["stdout"]))
    except ValueError as error:
        evidence.update(status="FAILED", diagnostic=f"Invalid evidence JSON: {error}")
        return None
    return value


def audit_proofs(evidence: dict[str, object]) -> dict[str, object]:
    """Require every named theorem and only the declared trusted Lean axioms."""
    if evidence["status"] == "PASSED":
        rows = re.findall(r"'([^']+)' depends on axioms: \[([^\]]*)\]", str(evidence["stdout"]))
        actual = {name: [item.strip() for item in axioms.split(",") if item.strip()]
                  for name, axioms in rows}
        allowed = {"propext", "Classical.choice", "Quot.sound"}
        if set(actual) != set(THEOREMS) or any(set(axioms) - allowed for axioms in actual.values()):
            evidence.update(status="FAILED", diagnostic="Named theorem/axiom audit did not match declared scope")
        evidence["theorem_axioms"] = actual
    return evidence
