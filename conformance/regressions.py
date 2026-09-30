"""Signature-preserving deletion and kernel-checked freezing after mismatch resolution."""

from collections.abc import Callable
from dataclasses import replace
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.generated_program import Program
from conformance.model_check import acquire, compiled, prove

CLASSIFICATIONS = {"model bug", "harness bug", "documentation gap", "engine quirk deliberately modeled"}


def signature(answer: dict[str, Json]) -> tuple[Json, Json]:
    """Keep the classifier's first divergent position fixed during deletion."""
    return answer.get("verdict"), answer.get("position")


def minimize(program: Program, oracle: Callable[[Program], dict[str, Json]]) -> Program:
    """After Hypothesis shrinking, delete statements only when the same disagreement persists."""
    expected = signature(oracle(program))
    if expected[0] != "DISAGREE":
        raise ValueError("Only a confirmed disagreement can be minimized")
    changed = True
    while changed:
        changed = False
        for index in range(len(program.commands)):
            candidate = replace(program, commands=program.commands[:index] + program.commands[index + 1:])
            if signature(oracle(candidate)) == expected:
                program, changed = candidate, True
                break
    return program


def freeze(program: Program, runtime: Path, destination: Path, *, classification: str,
           resolution: str, injected: bool = False) -> dict[str, Json]:
    """Reacquire native truth and require a kernel proof before publishing resolved evidence."""
    if classification not in CLASSIFICATIONS or not resolution.strip():
        raise ValueError("A resolved mismatch needs an explicit classification and explanation")
    case, error = acquire(program.fixture(), runtime)
    if case is None:
        raise ValueError(str(error))
    answer = compiled(case, runtime, emit_lean=True)
    if answer["verdict"] != "AGREE":
        raise ValueError("Unresolved disagreement cannot enter the proven regression corpus")
    encoded = json.dumps(case, indent=2) + "\n"
    digest = hashlib.sha256(encoded.encode()).hexdigest()
    with TemporaryDirectory(prefix="regression-proof-") as directory:
        proof = Path(directory) / "Regression.lean"
        prove(answer["caseLean"], runtime, proof, case=case)
        source = proof.read_text()
    destination.mkdir(parents=True, exist_ok=True)
    if any(destination.iterdir()):
        raise ValueError("Refusing to overwrite frozen regression evidence")
    (destination / "case.json").write_text(encoded)
    (destination / "Regression.lean").write_text(source)
    entry: dict[str, Json] = {"classification": classification, "resolution": resolution,
                             "injected": injected, "caseSha256": digest, "status": "resolved"}
    (destination / "mismatch.json").write_text(json.dumps(entry, indent=2) + "\n")
    return entry
