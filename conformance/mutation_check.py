"""Kill isolated production-model mutants using the exact generated native cases."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory

from conformance.case_format import Json
from conformance.model_check import compiled_many

MUTANTS = {
    "update_ignored": ("SqlExecution", "LiteralData.updated table column value key equals", "table"),
    "add_unpadded": ("Execution", "table.appendColumns [column]", "{ table with columns := table.columns ++ [column] }"),
    "rollback_ignored": ("SqlExecution", ".next { database := original }", ".next { database := state.database }"),
    "unique_disabled": ("LiteralData", "table.properties.keys.all (fun key => uniqueRows table key table.rows)", "true"),
}


def measure(cases: list[dict[str, Json]], runtime: Path) -> dict[str, Json]:
    """Compile mutated definitions in private namespaces; never rewrite the model or native truth."""
    root = Path(__file__).resolve().parents[1]
    answers = compiled_many(cases, runtime, emit_lean=True)
    admitted = [(case, answer) for case, answer in zip(cases, answers, strict=True) if answer["verdict"] == "AGREE"]
    terms = ",\n".join(answer["caseLean"] for _, answer in admitted)
    source = ("import VerifierConformance.Case\nset_option maxRecDepth 100000\n"
              "set_option maxHeartbeats 100000000\n"
              "def originals : List SqliteVerifier.Conformance.Case := [\n" + terms + "\n]\n")
    hashes: dict[str, str] = {}
    for name, (target, before, after) in MUTANTS.items():
        for filename in ("SqliteVerifier/Execution.lean", "SqliteVerifier/LiteralData.lean",
                         "SqliteVerifier/SqlExecution.lean", "VerifierConformance/Trace.lean", "VerifierConformance/Case.lean"):
            text = (root / filename).read_text()
            hashes[filename] = hashlib.sha256(text.encode()).hexdigest()
            if Path(filename).stem == target:
                assert text.count(before) == 1, (name, before)
                text = text.replace(before, after)
            if Path(filename).stem == "Execution":
                # Reuse production Statement/Outcome types; only the step definition is shadowed.
                text = "namespace SqliteVerifier\n" + text[text.index("def step "):text.index("/-- Restricted extension helper")]
                text += "\nend SqliteVerifier\n"
            text = "\n".join(line for line in text.splitlines() if not line.startswith("import "))
            text = text.replace("namespace SqliteVerifier", f"namespace SqliteVerifier.{name}")
            text = text.replace("end SqliteVerifier", f"end SqliteVerifier.{name}")
            source += text + "\n"
        fields = ("version", "schemaSql", "migrationSql", "schema", "initial", "script", "nativeTrace", "requirements", "provenance")
        # NativeObservation is namespace-local too, so copy its unchanged data fields explicitly.
        native = "c.nativeTrace.map fun n => { visible := n.visible, persisted := n.persisted, transactionOpen := n.transactionOpen, primaryCode := n.primaryCode, extendedCode := n.extendedCode }"
        conversion = ", ".join(field + " := " + ("(" + native + ")" if field == "nativeTrace" else "c." + field) for field in fields)
        source += f'\ndef convert_{name} (c : SqliteVerifier.Conformance.Case) : SqliteVerifier.{name}.Conformance.Case := {{ {conversion} }}\n'
        source += f'#eval IO.println (String.intercalate "\\n" (originals.zipIdx.map fun (c, i) => s!"MUTANT|{name}|{{i}}|{{reprStr (SqliteVerifier.{name}.Conformance.classifyCase (convert_{name} c))}}"))\n'
    with TemporaryDirectory(prefix="model-mutants-") as directory:
        lean = Path(directory) / "Mutants.lean"
        lean.write_text(source)
        result = subprocess.run([str(runtime / "lean/bin/lean"), str(lean)],
            env={**os.environ, "LEAN_PATH": str(runtime / ".lake/build/lib/lean")},
            capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    report: dict[str, Json] = {}
    for name in MUTANTS:
        verdicts = re.findall(r"^MUTANT\|" + name + r"\|(\d+)\|(.+)$", result.stdout, re.MULTILINE)
        assert len(verdicts) == len(admitted), (name, result.stdout)
        kills = [{"caseIndex": int(index), "verdict": verdict,
                  "migrationSql": admitted[int(index)][0]["migrationSql"]}
                 for index, verdict in verdicts if ".disagree" in verdict]
        report[name] = {"killed": bool(kills), "killCount": len(kills), "firstKill": kills[0] if kills else None,
                       "unsupported": sum(".modelUnsupported" in verdict for _, verdict in verdicts)}
    return {"admittedCases": len(admitted), "caseCount": len(cases), "sourceSha256": hashes, "mutants": report}


def main() -> None:
    """Measure an existing fixed-seed run without adding hand-picked mutation fixtures."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", type=Path)
    parser.add_argument("--runtime-root", type=Path, default=Path("build/conformance"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = measure([json.loads(line) for line in args.cases.read_text().splitlines()], args.runtime_root.resolve())
    report["casesSha256"] = hashlib.sha256(args.cases.read_bytes()).hexdigest()
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["mutants"]))
    assert all(mutant["killed"] for mutant in report["mutants"].values()), report


if __name__ == "__main__":
    main()
