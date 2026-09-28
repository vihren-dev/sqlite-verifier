"""Assemble evidence only from complete passing cases belonging to one fresh source run."""

from collections.abc import Callable
import hashlib
import json
from pathlib import Path

from atuin_sql_check import CASES
from import_fixture import fixture
from model_cases import cases


class Receipts:
    """A run-local view of reports; stale, duplicated or incomplete cases cannot supply evidence."""

    def __init__(self, directory: Path, run_id: str) -> None:
        self.directory = directory.resolve()
        self.run_id = run_id
        self.cases: dict[str, dict[str, object]] = {}
        self.failed_suites: set[str] = set()
        for path in sorted(directory.glob("*.json")):
            report = json.loads(path.read_text())
            if not isinstance(report, dict):
                raise ValueError(f"Case report must be a JSON object: {path}")
            if report.get("run_id") != run_id or report.get("runtime") != "source":
                continue
            rows = report.get("cases")
            if not isinstance(rows, list) or not all(isinstance(case, dict) and isinstance(case.get("node_id"), str) for case in rows):
                raise ValueError(f"Case report must contain named case objects: {path}")
            for case in rows:
                node = case["node_id"]
                if node in self.cases:
                    raise ValueError(f"Duplicate current-run evidence case: {node}")
                self.cases[node] = case
                if report.get("exit_code") != 0:
                    self.failed_suites.add(node)

    def passing(self, node: str) -> None:
        """Require setup, call and teardown success rather than a receipt file or process exit alone."""
        phases = self.cases.get(node, {}).get("phases")
        if node in self.failed_suites:
            raise ValueError(f"Current-run evidence suite failed: {node}")
        if not isinstance(phases, dict) or set(phases) != {"setup", "call", "teardown"}:
            raise ValueError(f"Missing current-run phases: {node}")
        if any(not isinstance(phase, dict) or phase.get("outcome") != "passed" or phase.get("timed_out") for phase in phases.values()):
            raise ValueError(f"Current-run evidence case did not pass: {node}")

    def data(self, node: str, filename: str) -> object:
        """Bind receipt contents to readable case metadata and the runtime/node/run directory identity."""
        self.passing(node)
        digest = hashlib.sha256(json.dumps(["source", node]).encode()).hexdigest()
        expected = self.directory / "artifacts" / digest / self.run_id
        actual = Path(str(self.cases[node].get("artifacts", ""))).resolve()
        if actual != expected:
            raise ValueError(f"Receipt directory does not match current-run case: {node}")
        metadata = json.loads((actual / "case.json").read_text())
        if metadata != {"runtime": "source", "node_id": node, "run_id": self.run_id}:
            raise ValueError(f"Stale or mismatched receipt metadata: {node}")
        return json.loads((actual / filename).read_text())


def captured(action: Callable[[], dict[str, object]]) -> dict[str, object]:
    """Unavailable evidence becomes an explicit failed check and never a fabricated match."""
    try:
        return action()
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        return {"status": "FAILED", "diagnostic": str(error)}


def checks_from_receipts(root: Path, directory: Path, run_id: str) -> dict[str, dict[str, object]]:
    """Reuse each producer once, preserving the pre-pytest coverage schema and denominators."""
    names = ("proof_build", "parser_regressions", "upstream_native", "derived_native_model",
             "atuin_sql", "grammar_export", "grammar_346_export", "named_proofs")
    try:
        receipts = Receipts(directory, run_id)
        inventory = json.loads((root / "tests/case-inventory.json").read_text())["cases"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {name: {"status": "FAILED", "diagnostic": str(error)} for name in names}

    def require_module(module: str) -> list[str]:
        """Check every inventoried producer case, including its negative and fidelity controls."""
        nodes = [case["node_id"] for case in inventory if case["node_id"].startswith(f"tests/{module}::")]
        if not nodes or len(nodes) != len(set(nodes)):
            raise ValueError(f"Missing or duplicated evidence inventory: {module}")
        for node in nodes:
            receipts.passing(node)
        return nodes

    def evidence(case: str, filename: str) -> dict[str, object]:
        """Require the bounded command receipt to carry its original success status."""
        value = receipts.data(f"tests/coverage_evidence_test.py::{case}", filename)
        if not isinstance(value, dict) or value.get("status") != "PASSED":
            raise ValueError(f"Failed command receipt: {case}")
        return value

    def rows(module: str, function: str, parameters: list[str], filename: str) -> list[object]:
        """Concatenate only the explicitly selected single-case receipts in declared case order."""
        require_module(module)
        result = []
        for parameter in parameters:
            value = receipts.data(f"tests/{module}::{function}[{parameter}]", filename)
            if not isinstance(value, list) or len(value) != 1:
                raise ValueError(f"Expected one observation: {module}[{parameter}]")
            result.extend(value)
        return result

    def structured(value: object) -> dict[str, object]:
        """Retain the established JSON evidence envelope without launching another subprocess."""
        return {"status": "PASSED", "stdout": json.dumps(value), "source": "fresh pytest receipts", "run_id": run_id}

    def parser() -> dict[str, object]:
        """Count passing authored grammar scripts separately from grammar-production coverage."""
        nodes = require_module("parser_test.py")
        lines = []
        for version in ("3.51.0", "3.46.0"):
            count = sum(node.startswith(f"tests/parser_test.py::test_valid_grammar[{version}-") for node in nodes)
            if not count:
                raise ValueError(f"Missing authored grammar denominator: {version}")
            lines.append(f"{version} parser checks passed: {count} grammar scripts")
        return {"status": "PASSED", "stdout": "\n".join(lines), "source": "fresh pytest receipts", "run_id": run_id}

    def upstream() -> dict[str, object]:
        """Join independently selected upstream calls with the independently checked final replay."""
        require_module("conformance_native_test.py")
        prefix = "tests/conformance_native_test.py::"
        final = receipts.data(prefix + "test_final_native_observations", "upstream-final.json")
        if not isinstance(final, dict):
            raise ValueError("Missing final upstream observations")
        observations = []
        for case in fixture()["cases"]:
            parameter = f"{case['upstream_id']}-{case['occurrence']}"
            value = receipts.data(prefix + f"test_upstream_case[{parameter}]", "upstream-native.json")
            if not isinstance(value, dict) or not isinstance(value.get("cases"), list) or len(value["cases"]) != 1:
                raise ValueError(f"Expected one upstream observation: {parameter}")
            observations.extend(value["cases"])
        return structured({**final, "cases": observations})

    return {
        "proof_build": captured(lambda: evidence("test_proof_build", "proof-build.json")),
        "parser_regressions": captured(parser),
        "upstream_native": captured(upstream),
        "derived_native_model": captured(lambda: structured(rows("conformance_model_test.py", "test_native_model",
            [case.name for case in cases()], "native-model.json"))),
        "atuin_sql": captured(lambda: structured(rows("atuin_sql_test.py", "test_native_history", list(CASES), "native-history.json"))),
        "grammar_export": captured(lambda: evidence("test_grammar_inventory[3.51.0]", "grammar.json")),
        "grammar_346_export": captured(lambda: evidence("test_grammar_inventory[3.46.0]", "grammar.json")),
        "named_proofs": captured(lambda: evidence("test_named_proofs", "named-proofs.json")),
    }
