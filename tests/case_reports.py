"""Separate runtime variants and preserve phase failures even when setup never completes."""

from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
from typing import TypedDict
from uuid import uuid4
import xml.etree.ElementTree as ET

import pytest

from tests.catalogue import CaseDescription


class PhaseReport(TypedDict):
    """Observable outcome and time for a single pytest execution phase."""

    outcome: str
    duration: float
    diagnostic: str | None
    timed_out: bool


@dataclass
class RunReports:
    """One invocation's catalogue and reports, never shared between source and installed."""

    directory: Path
    runtime: str
    suite: str
    run_id: str = field(default_factory=lambda: uuid4().hex)
    cases: list[CaseDescription] = field(default_factory=list)
    phases: dict[str, dict[str, PhaseReport]] = field(default_factory=dict)
    failed: set[str] = field(default_factory=set)
    shared_artifacts: dict[str, str] = field(default_factory=dict)

    def artifact_path(self, node_id: str) -> Path:
        """Include the full identity and runtime in a filesystem-safe content digest."""
        digest = hashlib.sha256(json.dumps([self.runtime, node_id]).encode()).hexdigest()
        return self.directory / self.runtime / "artifacts" / digest / self.run_id

    def artifacts(self, node_id: str) -> Path:
        """Create readable identity metadata only during execution, never collection."""
        destination = self.artifact_path(node_id)
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "case.json").write_text(json.dumps(
            {"runtime": self.runtime, "node_id": node_id, "run_id": self.run_id}, indent=2) + "\n")
        return destination

    def suite_artifacts(self) -> Path:
        """Qualify watchdog/checkpoint artifacts by runtime, suite and invocation identity."""
        return self.artifact_path(f"suite:{self.suite}")

    def checkpoint_selection(self) -> None:
        """Preserve the collected identities once, before a suite watchdog can kill pytest."""
        destination = self.suite_artifacts()
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "selection.json").write_text(json.dumps({
            "runtime": self.runtime, "suite": self.suite, "run_id": self.run_id,
            "selected_node_ids": [case["node_id"] for case in self.cases]}, indent=2) + "\n")

    def interrupted(self, selection: tuple[str, ...], code: int, diagnostic: str,
                    elapsed: float, timed_out: bool) -> None:
        """Report a runner failure and retain partial reports without inventing pytest phases."""
        directory, artifacts = self.directory / self.runtime, self.suite_artifacts()
        artifacts.mkdir(parents=True, exist_ok=True)
        for suffix in ("json", "xml"):
            existing = directory / f"{self.suite}.{suffix}"
            if existing.exists():
                existing.replace(artifacts / f"pytest.{suffix}")
        nodes = [node for node in selection if "::" in node]
        selection_status = "requested" if len(nodes) == len(selection) else "unavailable"
        try:
            checkpoint = json.loads((artifacts / "selection.json").read_text())
            actual = checkpoint["selected_node_ids"]
            if (checkpoint.get("runtime") != self.runtime or checkpoint.get("suite") != self.suite
                    or checkpoint.get("run_id") != self.run_id or not isinstance(actual, list)
                    or not all(isinstance(node, str) for node in actual)
                    or len(actual) != len(set(actual))
                    or (selection_status == "requested" and sorted(actual) != sorted(nodes))):
                raise ValueError("Suite selection checkpoint does not match the invocation")
            nodes, selection_status = actual, "collected"
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            diagnostic += f"\nSelection checkpoint unavailable: {error}"
        provenance = {"runtime": self.runtime, "suite": self.suite, "run_id": self.run_id,
                      "selection": json.dumps(selection), "selected_node_ids": json.dumps(nodes),
                      "selection_status": selection_status, "command_artifacts": str(artifacts),
                      "case_phases": "unavailable: pytest did not complete its suite report"}
        report = {**provenance, "selection": list(selection), "selected_node_ids": nodes,
                  "exit_code": code, "timed_out": timed_out, "elapsed": elapsed,
                  "diagnostic": diagnostic, "cases": [{"node_id": node, "phases": {}} for node in nodes]}
        (directory / f"{self.suite}.json").write_text(json.dumps(report, indent=2) + "\n")
        root = ET.Element("testsuites")
        summary = ET.SubElement(root, "testsuite", name=self.suite, tests="1", errors="1", failures="0",
                                time=str(elapsed))
        properties = ET.SubElement(summary, "properties")
        for name, value in provenance.items():
            ET.SubElement(properties, "property", name=name, value=value)
        case = ET.SubElement(summary, "testcase", classname="suite_runner", name="suite execution",
                             time=str(elapsed))
        ET.SubElement(case, "error", type="SuiteTimeout" if timed_out else "SuiteFailure",
                      message="Suite failed; case phase outcomes unavailable").text = diagnostic
        ET.ElementTree(root).write(directory / f"{self.suite}.xml", encoding="utf-8", xml_declaration=True)

    def observe(self, report: pytest.TestReport, *, timed_out: bool = False) -> None:
        """Store setup, call and teardown, including errors before a fixture exists."""
        diagnostic = report.longreprtext if report.failed or report.skipped else None
        self.phases.setdefault(report.nodeid, {})[report.when] = {
            "outcome": report.outcome, "duration": report.duration, "diagnostic": diagnostic,
            "timed_out": timed_out,
        }
        if report.failed:
            self.failed.add(report.nodeid)
            path = self.artifacts(report.nodeid)
            (path / f"{report.when}.txt").write_text(
                "\n".join([report.longreprtext, report.capstdout, report.capstderr]), encoding="utf-8")

    def write(self, exit_code: int) -> None:
        """Keep aggregate outcomes on success and failure without replacing the other runtime."""
        path = self.directory / self.runtime / f"{self.suite}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        rows = [{**case, "phases": self.phases.get(case["node_id"], {}),
                 "artifacts": str(self.artifact_path(case["node_id"])),
                 "failure_artifacts": str(self.artifact_path(case["node_id"]))
                 if case["node_id"] in self.failed else None} for case in self.cases]
        path.write_text(json.dumps({"runtime": self.runtime, "suite": self.suite, "run_id": self.run_id,
                                   "shared_artifacts": self.shared_artifacts,
                                   "exit_code": exit_code, "cases": rows}, indent=2) + "\n")


REPORTS = pytest.StashKey[RunReports]()
