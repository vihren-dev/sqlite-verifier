"""Refuse independent receipt corruption with bounded reads and no native replay."""

from copy import deepcopy
from typing import Callable

import validate as evidence


def expect_refusal(label: str, check: Callable[[], None]) -> None:
    """A corrupted observation must fail even when its JSON still has valid shape."""
    try:
        check()
    except AssertionError:
        return
    raise AssertionError(f"Corrupt evidence was accepted: {label}")


def check_mutations() -> None:
    """Test identity, native hash, fixture order and target fields independently."""
    evidence.validate()
    original = evidence.document
    summary = evidence.decode((evidence.ROOT / "receipt.json").read_bytes())
    source = original("source-manifest.json")

    def changed_document(name: str) -> dict[str, evidence.Json]:
        """Apply one observation change while retaining other original artifacts."""
        value = deepcopy(original(name))
        if mutation == "selected identity" and name == "linux/report.json":
            identities = evidence.mapping(value["generic"])["selectedIdentities"]
            assert isinstance(identities, list)
            evidence.mapping(identities[0])["name"] = "corrupt-selected-name"
        elif mutation == "native library" and name == "linux/identity-after.json":
            evidence.mapping(evidence.mapping(value["nativeLibraries"])["3.51.0"])["sha256"] = "0" * 64
        elif mutation == "fixture uniqueness" and name in ("linux/phase-result.json", "linux/receipt.json"):
            phase = evidence.mapping(value["phase"]) if name.endswith("receipt.json") else value
            paths = phase["fixturePaths"]
            assert isinstance(paths, list)
            paths[1] = paths[0]
        return value

    try:
        evidence.document = changed_document
        for mutation in ("selected identity", "native library", "fixture uniqueness"):
            expect_refusal(mutation, lambda: evidence.check_platform("linux", summary, source))
    finally:
        evidence.document = original
    changed = deepcopy(summary)
    evidence.mapping(evidence.mapping(changed["platforms"])["linux"])["underTarget"] = True
    expect_refusal("Linux target miss", lambda: evidence.check_platform("linux", changed, source))
    print("Four corrupt identity, native hash, fixture and target observations are refused.")


if __name__ == "__main__":
    check_mutations()
