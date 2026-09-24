"""Run bounded evidence commands and preserve errors without manufacturing a passing result."""

import json
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory
from collections.abc import Sequence

from coverage_catalog import THEOREMS


def command(arguments: Sequence[str], root: Path, timeout: int) -> dict[str, object]:
    """A failing or timed-out check remains a failure with an inspectable diagnostic."""
    try:
        completed = subprocess.run(arguments, cwd=root, capture_output=True, text=True, timeout=timeout)
        return {"status": "PASSED" if completed.returncode == 0 else "FAILED",
                "exit_code": completed.returncode, "stdout": completed.stdout,
                "stderr": completed.stderr, "command": list(arguments)}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"status": "FAILED", "diagnostic": str(error), "command": list(arguments)}


def structured(evidence: dict[str, object]) -> object:
    """Parse runner output only after success; bad output cannot count as zero discrepancies."""
    if evidence["status"] != "PASSED":
        return None
    try:
        value = json.loads(str(evidence["stdout"]))
    except ValueError as error:
        evidence.update(status="FAILED", diagnostic=f"Invalid evidence JSON: {error}")
        return None
    return value


def proof_probe(root: Path) -> dict[str, object]:
    """Inspect the declared theorem set in the freshly built trusted library, separately from the CLI gate."""
    with TemporaryDirectory(prefix="coverage-proof-") as directory:
        source = Path(directory) / "Audit.lean"
        source.write_text("import SqliteVerifier\n" + "\n".join(
            f"#check {name}\n#print axioms {name}" for name in THEOREMS) + "\n")
        evidence = command(["lake", "env", "lean", str(source)], root, 30)
    if evidence["status"] == "PASSED":
        rows = re.findall(r"'([^']+)' depends on axioms: \[([^\]]*)\]", str(evidence["stdout"]))
        actual = {name: [item.strip() for item in axioms.split(",") if item.strip()]
                  for name, axioms in rows}
        allowed = {"propext", "Classical.choice", "Quot.sound"}
        if set(actual) != set(THEOREMS) or any(set(axioms) - allowed for axioms in actual.values()):
            evidence.update(status="FAILED", diagnostic="Named theorem/axiom audit did not match declared scope")
        evidence["theorem_axioms"] = actual
    return evidence
