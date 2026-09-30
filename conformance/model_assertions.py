"""Render tier-two proofs of the same predicate used by the compiled classifier."""

from textwrap import indent

from migration_check.sql_model import lean_string


def audit_axioms(output: str) -> None:
    """Reject proof-oracle dependencies, including Lean's per-use native axiom names."""
    if any(token in output for token in ("sorryAx", "ofReduceBool", "_native")):
        raise AssertionError(output)


def assertions(term: str, encoded: str, *, expected: bool = True, failure: str | None = None) -> str:
    """Embed the runner's decoded structural case, never a separate comparison implementation."""
    preserved = "" if failure is None else (
        "theorem preservedFailure : (observeOutcome fixture.names "
        "(SqliteVerifier.runSql fixture.script (databaseOf fixture.initial))).error = " + failure +
        " := by decide +kernel\n#print axioms preservedFailure\n")
    return ("import VerifierConformance.Json\n"
            "open SqliteVerifier.Conformance\n"
            "set_option maxRecDepth 100000\nset_option maxHeartbeats 30000000\n"
            "def fixture : Case :=\n" + indent(term, "  ") + "\n" +
            f"#guard match Lean.Json.parse {lean_string(encoded)} with\n"
            "  | .ok json => json == Lean.toJson fixture\n  | .error _ => false\n"
            f"theorem checkedCase : checkCase fixture = {str(expected).lower()} := by decide +kernel\n"
            "#print axioms checkedCase\n#print axioms unsupported_not_checked\n#print axioms trace_final\n" + preserved)
