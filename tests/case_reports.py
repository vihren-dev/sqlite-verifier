"""Separate runtime variants and preserve phase failures even when setup never completes."""

from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
from typing import TypedDict
from uuid import uuid4

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
