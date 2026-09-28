"""Retain honest current-run evidence when pytest cannot finish writing its own reports."""

import json
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

import pytest

from tests.test_pytest_harness import ROOT, harness
from tests.runtime_support import run_command
from tools import run_source_suite
from tools.run_independent_suites import run_suites

pytestmark = [pytest.mark.integration, pytest.mark.environment]
NODE = "tests/test_probe.py::test_probe"


@pytest.mark.parametrize("scenario", [
    pytest.param("timeout", marks=pytest.mark.requires_native("/bin/ps")),
    pytest.param("partial-timeout", marks=pytest.mark.requires_native("/bin/ps")),
    "missing-report",
])
def test_interrupted_suite_retains_provenance(harness: Path, monkeypatch: pytest.MonkeyPatch,
                                            scenario: str) -> None:
    """Outer deadlines or absent reports fail with exact selection and unavailable case phases."""
    monkeypatch.chdir(harness)
    reports = harness / "custom-results/source"
    reports.mkdir(parents=True)
    for suffix in ("json", "xml"):
        (reports / f"test_probe.{suffix}").write_text("stale report")
    installed = harness / "custom-results/installed/test_probe.json"
    installed.parent.mkdir(parents=True)
    installed.write_text("installed report")
    body = '    print("case reached", flush=True)\n'
    if scenario == "partial-timeout":
        body += ('    from tests.case_reports import REPORTS\n'
                 '    request.config.stash[REPORTS].write(0)\n'
                 '    Path("custom-results/source/test_probe.xml").write_text("<testsuites/>")\n')
    if scenario != "missing-report":
        body += "    time.sleep(60)\n"
    else:
        with (harness / "conftest.py").open("a") as stream:
            stream.write('\ndef pytest_sessionfinish(session, exitstatus):\n    pass\n')
    (harness / "tests/test_probe.py").write_text(
        'import pytest,time\nfrom pathlib import Path\npytestmark=pytest.mark.integration\n'
        'def test_probe(request):\n    """Reach the outer suite deadline."""\n' + body)
    deadline = 30 if scenario == "missing-report" else 3
    assert run_suites((("tests/test_probe.py", deadline),), max_workers=1,
                      run_id="current", selections={"tests/test_probe.py": (NODE,)},
                      pytest_args=("-s",), report_dir=harness / "custom-results") == 1
    report = json.loads((reports / "test_probe.json").read_text())
    assert report["runtime"] == "source" and report["run_id"] == "current"
    assert report["selection"] == report["selected_node_ids"] == [NODE]
    assert report["selection_status"] == "collected"
    assert report["exit_code"] == (1 if scenario == "missing-report" else 124)
    assert report["timed_out"] == (scenario != "missing-report")
    assert report["cases"] == [{"node_id": NODE, "phases": {}}]
    assert "unavailable" in report["case_phases"]
    artifacts = Path(report["command_artifacts"])
    command = json.loads((artifacts / "command-0000.json").read_text())
    assert command["timed_out"] == report["timed_out"] and "case reached" in command["stdout"]
    assert NODE in command["command"] and "--run-id" in command["command"]
    xml = ET.parse(reports / "test_probe.xml")
    assert xml.find(".//testcase").attrib == {
        "classname": "suite_runner", "name": "suite execution", "time": str(report["elapsed"])}
    assert xml.find(".//error") is not None
    properties = {row.attrib["name"]: row.attrib["value"] for row in xml.findall(".//property")}
    assert properties["run_id"] == "current" and properties["runtime"] == "source"
    assert json.loads(properties["selection"]) == [NODE]
    assert installed.read_text() == "installed report"
    if scenario == "partial-timeout":
        partial = json.loads((artifacts / "pytest.json").read_text())
        assert partial["run_id"] == "current" and partial["exit_code"] == 0
        setup = partial["cases"][0]["phases"]["setup"]
        assert setup["outcome"] == "passed" and setup["duration"] >= 0
        assert (artifacts / "pytest.xml").read_text() == "<testsuites/>"
    else:
        assert not (artifacts / "pytest.json").exists()
    monkeypatch.syspath_prepend(str(ROOT / "conformance"))
    from coverage_receipts import Receipts
    with pytest.raises(ValueError, match="Current-run evidence suite failed"):
        Receipts(reports, "current").passing(NODE)


@pytest.mark.parametrize("scenario", ["collection-error",
    pytest.param("collection-timeout", marks=pytest.mark.requires_native("/bin/ps")),
    "aggregation-error", pytest.param("cache-error", marks=pytest.mark.requires_nix)])
def test_early_failure_writes_fresh_coverage(harness: Path, monkeypatch: pytest.MonkeyPatch,
                                          capsys: pytest.CaptureFixture[str], scenario: str) -> None:
    """Collection/cache failures still aggregate fresh failed evidence and retain original diagnostics."""
    monkeypatch.chdir(harness)
    monkeypatch.setattr(run_source_suite, "ROOT", harness)
    if scenario == "collection-timeout":
        monkeypatch.setitem(run_source_suite.DEADLINES, "collection", 3)
    monkeypatch.setenv("SQLITE_VERIFIER_RUNTIME_ROOT", str(harness))
    monkeypatch.delenv("SQLITE_VERIFIER_UNIT_CHECKS", raising=False)
    shutil.copytree(ROOT / "conformance", harness / "conformance",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copy2(ROOT / "tests/case-inventory.json", harness / "tests")
    (harness / "build").mkdir()
    (harness / "build/coverage.json").write_text('{"run_id":"old","status":"EVIDENCE_CHECKS_PASSED"}')
    (harness / "build/source-catalogue.json").write_text('[{"node_id":"stale"}]')
    if scenario == "collection-timeout":
        source = 'import time\nprint("collection reached",flush=True)\ntime.sleep(60)\n'
    elif scenario == "cache-error":
        monkeypatch.setenv("SQLITE_VERIFIER_UNIT_CHECKS", str(harness / "missing-cache"))
        source = 'import pytest\n@pytest.mark.unit\ndef test_probe():\n    """Collect before cache validation."""\n'
    else:
        source = 'raise RuntimeError("collection-broken")\n'
    (harness / "tests/test_probe.py").write_text(source)
    if scenario == "aggregation-error":
        (harness / "conformance/coverage_report.py").write_text('raise RuntimeError("aggregate-broken")\n')
    assert run_source_suite.main() != 0
    output = capsys.readouterr()
    coverage = json.loads((harness / "build/coverage.json").read_text())
    assert coverage["status"] == "EVIDENCE_CHECKS_FAILED" and coverage["run_id"] != "old"
    diagnostic = {"collection-timeout": "Command timed out", "cache-error": "unit derivation"}.get(
        scenario, "collection-broken")
    assert diagnostic in coverage["orchestration_diagnostic"] and diagnostic in output.err
    if scenario == "aggregation-error":
        assert "aggregate-broken" in output.out
        assert "aggregate-broken" in coverage["diagnostic"]
    artifacts = harness / "build/test-logs/source-collection" / coverage["run_id"]
    command = json.loads((artifacts / "command-0000.json").read_text())
    assert coverage["run_id"] in command["command"]
    assert command["timed_out"] == (scenario == "collection-timeout")
    if (harness / "build/source-catalogue.json").exists():
        assert "stale" not in (harness / "build/source-catalogue.json").read_text()
    assert (harness / "build/test-logs/source-coverage" / coverage["run_id"] / "command-0000.json").is_file()


@pytest.mark.requires_native("/bin/ps")
def test_installed_watchdog_cleans_nested_command(harness: Path) -> None:
    """Installed CLI timeouts kill detached commands and preserve module-selected identities separately."""
    child = ('import os,time\nfrom pathlib import Path\n'
             'assert "ambient imports" in os.environ["PYTHONPATH"]\n'
             f'Path({str(harness / "child.pid")!r}).write_text(str(os.getpid()))\n'
             'time.sleep(60)\n')
    (harness / "tests/test_probe.py").write_text(
        'import pytest,sys\npytestmark=pytest.mark.integration\n'
        'def test_probe(command_runner,tmp_path):\n    """Run an installed nested child."""\n'
        f'    command_runner([sys.executable,"-I","-c",{child!r}],cwd=tmp_path,timeout=30)\n')
    source = harness / "build/test-results/source/installed.json"
    source.parent.mkdir(parents=True)
    source.write_text("source report")
    result = run_command([sys.executable, str(ROOT / "tools/run_independent_suites.py"),
                          "--timeout", "3", "--suite", "installed", "--runtime-variant", "installed",
                          "--runtime-archive", "absent.tar.gz", "--", "tests/test_probe.py"],
                         cwd=harness, timeout=15)
    assert result.returncode == 1, result.diagnostic()
    report = json.loads((harness / "build/test-results/installed/installed.json").read_text())
    assert report["runtime"] == "installed" and report["exit_code"] == 124
    assert report["selected_node_ids"] == [NODE] and report["selection_status"] == "collected"
    assert report["selection"] == ["tests/test_probe.py"] and report["cases"][0]["phases"] == {}
    checkpoint = json.loads((Path(report["command_artifacts"]) / "selection.json").read_text())
    assert checkpoint["suite"] == "installed" and checkpoint["run_id"] == report["run_id"]
    command = json.loads((Path(report["command_artifacts"]) / "command-0000.json").read_text())
    assert "--runtime-archive" in command["command"] and "--runtime-root" not in command["command"]
    assert command["cleanup_error"] is None and command["timed_out"]
    pid = (harness / "child.pid").read_text()
    status = run_command(["/bin/ps", "-o", "stat=", "-p", pid], cwd=harness, timeout=2)
    assert not status.stdout.strip() or status.stdout.strip().startswith("Z")
    assert source.read_text() == "source report"
