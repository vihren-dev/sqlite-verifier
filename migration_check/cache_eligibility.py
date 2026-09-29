"""Approved closures qualified for stage reuse after a determinism review (ADR 0002 §6.1).

An entry is the digest of an exact approved module/source-hash map. It may be added
only with a linked review showing that elaborating that closure depends on nothing
but its identified inputs. Business approval or a matching user baseline never
grants eligibility. The registry is intentionally empty.
"""

from .stage_store import StageStore

ELIGIBLE_APPROVED_CLOSURES: frozenset[str] = frozenset()
"""Reviewed approved-closure digests; empty until a review is recorded."""


def approved_reuse_allowed(closure_digest: str, store: StageStore) -> bool:
    """Reviewed closures, or any closure under the P1 measurement-only override."""
    return closure_digest in ELIGIBLE_APPROVED_CLOSURES or store.approved_eligible
