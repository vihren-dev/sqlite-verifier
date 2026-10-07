"""Run the real compiler inventory and fail the public documentation gate when coverage is incomplete."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.public_doc_coverage import coverage_report, mapping, position, sequence

COMPILER_TIMEOUT_SECONDS = 60
"""Bound both helper compilation and the source/metadata query independently."""


def inventory(root: Path, entry: str, lean: Path, output: Path) -> dict[str, object]:
    """Compile only the development helper and query the already built public import closure."""
    output.parent.mkdir(parents=True, exist_ok=True)
    work = output.parent / "public-doc-helper"
    work.mkdir(exist_ok=True)
    tools = Path(__file__).resolve().parent
    helper = work / "PublicDocSyntax.olean"
    environment = dict(os.environ)
    subprocess.run([str(lean), "-o", str(helper), str(tools / "PublicDocSyntax.lean")],
                   cwd=tools, env=environment, check=True, timeout=COMPILER_TIMEOUT_SECONDS)
    environment["LEAN_PATH"] = str(work) + os.pathsep + environment.get("LEAN_PATH", "")
    metadata = work / "metadata.json"
    subprocess.run([str(lean), "--run", str(tools / "PublicDocInventory.lean"),
                    str(root), entry, str(metadata)], cwd=tools, env=environment,
                   check=True, timeout=COMPILER_TIMEOUT_SECONDS)
    report = coverage_report(json.loads(metadata.read_text()))
    output.write_text(json.dumps(report, indent=2) + "\n")
    return report


def require_complete(report: dict[str, object], output: Path) -> bool:
    """Explain the source locations that keep the gate incomplete without hiding partial coverage."""
    counts = mapping(report["counts"], "inventory counts")
    print(json.dumps({"complete": report["complete"], "counts": counts, "report": str(output)}))
    if report["complete"] is True:
        return True
    for raw_module in sequence(report["modules"], "modules"):
        module = mapping(raw_module, "module")
        for raw in sequence(module["authored"], "authored declarations"):
            declaration = mapping(raw, "authored declaration")
            if declaration["verso"] is not True:
                selected = position(declaration["selection"], f"{module['source']}: {declaration['name']}")
                state = "ordinary documentation" if declaration["documented"] else "missing documentation"
                print(f"{module['source']}:{selected[0] + 1}:{selected[1]}: "
                      f"{declaration['name']}: {state}; add checked Verso documentation and rebuild")
        for raw in sequence(module["unclassified"], "unclassified declarations"):
            declaration = mapping(raw, "unclassified declaration")
            print(f"{module['source']}: {declaration}: inventory cannot classify this source; inspect the compiler metadata")
    return False


def main() -> int:
    """Accept an explicit source directory, imported entry point, compiler and retained report path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--entry", default="SqliteVerifier")
    parser.add_argument("--lean", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    root, output = arguments.root.resolve(), arguments.output.resolve()
    report = inventory(root, arguments.entry, arguments.lean.resolve(), output)
    complete = require_complete(report, output)
    return 0 if complete else 1


if __name__ == "__main__":
    raise SystemExit(main())
