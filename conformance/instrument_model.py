"""Instrument explicit match arms in an isolated copy of production execution definitions."""

import json
from pathlib import Path
import re
import sys

SCOPE = {"Execution.lean": {"step"}, "SqlExecution.lean": {
    "SqlState.finish", "literalStep", "statementReady", "advance", "runSqlFrom", "supportedSqlFrom"}}


def instrument(root: Path) -> None:
    """Insert identity debug traces; the shipped sources and classifier are never edited."""
    sites = []
    for name, functions in SCOPE.items():
        path = root / "SqliteVerifier" / name
        output = []
        active = ""
        for number, line in enumerate(path.read_text().splitlines(), 1):
            declaration = re.match(r"(?:def|theorem|inductive|structure|end)\s+(\S+)", line)
            if declaration:
                active = declaration[1] if line.startswith("def ") and declaration[1] in functions else ""
            if active and line.lstrip().startswith("|") and "=>" in line:
                site = f"{name}:{active}:{number}"
                sites.append({"id": site, "arm": line.strip().split("=>")[0]})
                line = line.replace("=>", '=> dbg_trace "COVER|' + site + '";', 1)
            output.append(line)
        text = "\n".join(output) + "\n"
        text = text.replace("namespace SqliteVerifier\n", "namespace SqliteVerifier\nattribute [simp] dbgTrace\n", 1)
        path.write_text(text)
    (root / "coverage-sites.json").write_text(json.dumps(sites, indent=2) + "\n")
    runner = root / "ConformanceRunner.lean"
    source = runner.read_text()
    original = '[("verdict", toJson name), ("position", toJson position)]'
    observed = '''[("verdict", toJson name), ("position", toJson position),
      ("executed", toJson (c.script.take ((trace c.names c.script (databaseOf c.initial)).length - 1))),
      ("modelError", toJson (reprStr (observeOutcome c.names
        (SqliteVerifier.runSql c.script (databaseOf c.initial))).error))]'''
    assert source.count(original) == 1
    runner.write_text(source.replace(original, observed))


if __name__ == "__main__":
    instrument(Path(sys.argv[1]))
