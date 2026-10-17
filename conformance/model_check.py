"""One-case native acquisition, compiled classification and kernel proof checking."""

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess

from belay.sqlite.errors import SqlError
from conformance.case_format import Json
from conformance.model_assertions import assertions, audit_axioms, batch_assertions
from conformance.native_trace import Fixture, record
from conformance.record_parser import default_parser


def compiled(case: dict[str, Json], runtime: Path, *, emit_lean: bool = False) -> dict[str, Json]:
    """Preserve the one-case API over the shared JSON-lines transport."""
    return compiled_many([case], runtime, emit_lean=emit_lean)[0]


def compiled_many(cases: list[dict[str, Json]], runtime: Path, *,
                  emit_lean: bool = False) -> list[dict[str, Json]]:
    """Classify a bounded batch through one runner process, preserving line order."""
    command = [str(runtime / ".lake/build/bin/conformance-runner")]
    if emit_lean:
        command.append("--emit-lean")
    result = subprocess.run(command, input="".join(json.dumps(case) + "\n" for case in cases),
                            text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    answers = [json.loads(line) for line in result.stdout.splitlines()]
    if len(answers) != len(cases) or any(
        not isinstance(answer, dict) or answer.get("verdict") not in {
            "AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR"
        } for answer in answers
    ):
        raise ValueError("Malformed compiled classifier response")
    return answers


def acquire(fixture: Fixture, runtime: Path) -> tuple[dict[str, Json] | None, dict[str, Json]]:
    """Keep acquisition errors separate from cases submitted to the model."""
    try:
        return record(fixture, default_parser(runtime)), {}
    except SqlError as error:
        return None, {"verdict": "MODEL_UNSUPPORTED" if error.status == "UNSUPPORTED" else "HARNESS_ERROR",
                      "error": str(error)}
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        return None, {"verdict": "HARNESS_ERROR", "error": str(error)}


def evaluate(fixture: Fixture, runtime: Path) -> tuple[dict[str, Json] | None, dict[str, Json]]:
    """Frontend rejections and native/transport failures cannot masquerade as agreement."""
    case, answer = acquire(fixture, runtime)
    if case is None:
        return case, answer
    try:
        return case, compiled(case, runtime)
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        return None, {"verdict": "HARNESS_ERROR", "error": str(error)}


def prove(term: str, runtime: Path, destination: Path, *, case: dict[str, Json], expected: bool = True,
          failure: str | None = None) -> str:
    """Kernel-check the runner's decoded closed term, keeping native code out of the proof."""
    destination.write_text(assertions(term, json.dumps(case, ensure_ascii=False), expected=expected, failure=failure))
    return kernel_check(runtime, destination)


def prove_batch(terms: list[str], runtime: Path, destination: Path, *, cases: list[dict[str, Json]]) -> str:
    """Kernel-check that several agreeing cases are true in one Lean process (`batch_assertions`)."""
    destination.write_text(batch_assertions([(term, json.dumps(case, ensure_ascii=False))
                                             for term, case in zip(terms, cases, strict=True)]))
    output = kernel_check(runtime, destination)
    if output.count("checkedCase' depends on axioms") != len(terms):
        raise AssertionError(f"Expected one checked proof for each of the {len(terms)} cases:\n{output}")
    return output


PROOF_BATCH = 8
"""Cases per kernel proof file of `prove_all`: Lean loads the imports once for each file, about
0.7 s, which is most of the time of a one-case proof."""


def prove_all(terms: list[str], runtime: Path, directory: Path, *, cases: list[dict[str, Json]],
              name: str = "Cases") -> None:
    """Kernel-check that every agreeing case is true, `PROOF_BATCH` cases per Lean process
    (`prove_batch`) and the processes in parallel, writing the proof files to `directory`."""
    starts = range(0, len(terms), PROOF_BATCH)
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        list(pool.map(lambda start: prove_batch(terms[start:start + PROOF_BATCH], runtime,
                                                directory / f"{name}{start}.lean",
                                                cases=cases[start:start + PROOF_BATCH]), starts))


def kernel_check(runtime: Path, destination: Path) -> str:
    """Run the pinned Lean on a proof file over the runtime's modules and audit its axioms."""
    checked = subprocess.run([str(runtime / "lean/bin/lean"), str(destination)],
                             env={**os.environ, "LEAN_PATH": os.pathsep.join(str(runtime / path) for path in (".lake/build/lib/lean", "packages/belay-sqlite/.lake/build/lib/lean"))},
                             capture_output=True, text=True, timeout=120)
    if checked.returncode:
        raise AssertionError(checked.stdout + checked.stderr)
    audit_axioms(checked.stdout)
    return checked.stdout
