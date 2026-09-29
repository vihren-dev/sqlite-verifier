"""One-case native acquisition, compiled classification and kernel proof checking."""

import json
import os
from pathlib import Path
import subprocess

from migration_check.diagnostics import Rejection
from conformance.case_format import Json
from conformance.model_assertions import assertions, audit_axioms
from conformance.native_trace import Fixture, record


def compiled(case: dict[str, Json], runtime: Path, *, emit_lean: bool = False) -> dict[str, Json]:
    """Python transports one case; only the compiled Lean classifier decides agreement."""
    command = [str(runtime / ".lake/build/bin/conformance-runner")]
    if emit_lean:
        command.append("--emit-lean")
    result = subprocess.run(command, input=json.dumps(case) + "\n", text=True,
                            capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    answer = json.loads(result.stdout)
    if not isinstance(answer, dict) or answer.get("verdict") not in {
        "AGREE", "DISAGREE", "MODEL_UNSUPPORTED", "HARNESS_ERROR"
    }:
        raise ValueError("Malformed compiled classifier response")
    return answer


def evaluate(fixture: Fixture, runtime: Path) -> tuple[dict[str, Json] | None, dict[str, Json]]:
    """Frontend rejections and native/transport failures cannot masquerade as agreement."""
    try:
        case = record(fixture, runtime / "build/sqlite-parser")
        return case, compiled(case, runtime)
    except Rejection as error:
        return None, {"verdict": "MODEL_UNSUPPORTED" if error.status == "UNSUPPORTED" else "HARNESS_ERROR",
                      "error": str(error)}
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        return None, {"verdict": "HARNESS_ERROR", "error": str(error)}


def prove(term: str, runtime: Path, destination: Path, *, expected: bool = True,
          failure: str | None = None) -> str:
    """Kernel-check the runner's decoded closed term, keeping native code out of the proof."""
    destination.write_text(assertions(term, expected=expected, failure=failure))
    checked = subprocess.run([str(runtime / "lean/bin/lean"), str(destination)],
                             env={**os.environ, "LEAN_PATH": str(runtime / ".lake/build/lib/lean")},
                             capture_output=True, text=True, timeout=120)
    if checked.returncode:
        raise AssertionError(checked.stdout + checked.stderr)
    audit_axioms(checked.stdout)
    return checked.stdout
