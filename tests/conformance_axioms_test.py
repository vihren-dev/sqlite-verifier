"""Guard the tier-two proof policy against per-use native axiom naming changes."""

import pytest

from conformance.model_assertions import audit_axioms

pytestmark = pytest.mark.unit


@pytest.mark.parametrize("axiom", ["sorryAx", "Lean.ofReduceBool", "checkedCase._native.1"])
def test_forbidden_axiom(axiom: str) -> None:
    """Every prohibited family is rejected even when ordinary logical axioms also appear."""
    with pytest.raises(AssertionError):
        audit_axioms(f"'checkedCase' depends on axioms: [propext, {axiom}, Quot.sound]")


def test_logical_axioms() -> None:
    """The product's ordinary logical axioms do not masquerade as native execution oracles."""
    audit_axioms("'checkedCase' depends on axioms: [propext, Classical.choice, Quot.sound]")
