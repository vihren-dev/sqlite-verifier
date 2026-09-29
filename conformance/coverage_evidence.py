"""Audit Lean `#print axioms` output against the catalogued theorems and trusted axioms."""

import re

from coverage_catalog import THEOREMS

TRUSTED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}


def theorem_axioms(output: str) -> dict[str, set[str]]:
    """Map each theorem named in Lean's `#print axioms` output to the axioms it depends on."""
    rows = re.findall(r"'([^']+)' depends on axioms: \[([^\]]*)\]", output)
    return {name: {item.strip() for item in axioms.split(",") if item.strip()} for name, axioms in rows}


def audit_problems(output: str) -> list[str]:
    """List missing or extra theorems and any axiom outside the trusted Lean allowance."""
    actual = theorem_axioms(output)
    problems = [f"missing theorem: {name}" for name in THEOREMS if name not in actual]
    problems += [f"unexpected theorem: {name}" for name in actual if name not in THEOREMS]
    problems += [f"{name} uses untrusted axioms: {sorted(axioms - TRUSTED_AXIOMS)}"
                 for name, axioms in actual.items() if axioms - TRUSTED_AXIOMS]
    return problems
