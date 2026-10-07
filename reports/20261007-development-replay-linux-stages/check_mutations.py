"""Refuse lost worker-stage evidence and independently corrupt child CPU counters."""

from copy import deepcopy

import validate as evidence


def check_mutations() -> None:
    """Corrupt decoded fields after byte checks to exercise stage consistency."""
    evidence.validate()
    original = evidence.document

    def changed(name: str) -> dict[str, evidence.Json]:
        """Apply one stage corruption while retaining the other original observations."""
        value = deepcopy(original(name))
        if name == "diagnostic/stage-observations.json":
            if mutation == "missing worker stage":
                value.pop("replay_native_cases")
            else:
                calls = value["replay_native_cases"]
                assert isinstance(calls, list)
                metrics = evidence.mapping(evidence.mapping(calls[0])["metricsDelta"])
                metrics["childrenUserSeconds"] = evidence.number(metrics["childrenUserSeconds"]) + 1
        return value

    try:
        evidence.document = changed
        for mutation in ("missing worker stage", "corrupt child CPU"):
            try:
                evidence.validate()
            except AssertionError:
                continue
            raise AssertionError(f"Corrupt stage evidence accepted: {mutation}")
    finally:
        evidence.document = original
    print("A missing worker stage and corrupt child CPU counter are refused.")


if __name__ == "__main__":
    check_mutations()
