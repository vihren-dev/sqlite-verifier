"""Render tier-two proofs of the same predicate used by the compiled classifier."""

from textwrap import indent

from belay.sqlite.quoted_text import quoted_string


def audit_axioms(output: str) -> None:
    """Reject proof-oracle dependencies, including Lean's per-use native axiom names."""
    if any(token in output for token in ("sorryAx", "ofReduceBool", "_native")):
        raise AssertionError(output)


HEADER = ("import VerifierConformance.Json\n"
          "open Belay.Sqlite.Conformance\n"
          "set_option maxRecDepth 100000\nset_option maxHeartbeats 30000000\n")
"""The imports and options of a proof file."""
FOOTER = "#print axioms unsupported_not_checked\n#print axioms trace_final\n"
"""The axiom reports of the general lemmas that every proof file checks."""


def case_assertions(term: str, encoded: str, *, expected: bool = True, failure: str | None = None) -> str:
    """The definitions and proofs of one case: the runner's decoded structural case, the check
    that it encodes to the recorded JSON, and the kernel proof of its verdict."""
    preserved = "" if failure is None else (
        "theorem preservedFailure : (modelOutcome fixture).map (fun outcome => (observeOutcome 0 outcome).error) = "
        "some (" + failure + ") := by decide +kernel\n#print axioms preservedFailure\n")
    return ("def fixture : Case :=\n" + indent(term, "  ") + "\n" +
            f"#guard match Lean.Json.parse {quoted_string(encoded)} with\n"
            "  | .ok json => json == Lean.toJson fixture\n  | .error _ => false\n"
            f"theorem checkedCase : checkCase fixture = {str(expected).lower()} := by decide +kernel\n"
            "#print axioms checkedCase\n" + preserved)


def assertions(term: str, encoded: str, *, expected: bool = True, failure: str | None = None) -> str:
    """Embed the runner's decoded structural case, never a separate comparison implementation."""
    return HEADER + case_assertions(term, encoded, expected=expected, failure=failure) + FOOTER


def batch_assertions(cases: list[tuple[str, str]]) -> str:
    """The proofs of several agreeing cases in one file, each in its own namespace, so Lean
    loads the imports once for all of them. Each item is a case term and its encoded case."""
    bodies = "".join(f"namespace Case{index}\n" + case_assertions(term, encoded) + f"end Case{index}\n"
                     for index, (term, encoded) in enumerate(cases))
    return HEADER + bodies + FOOTER
