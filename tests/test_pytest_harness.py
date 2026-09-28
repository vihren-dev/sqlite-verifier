"""Exercise discovery and failure reporting in a separate minimal pytest repository."""

import json
import os
from pathlib import Path
import shutil
import sys
import time

import pytest

from tests.runtime_support import CommandResult, CommandTimeout, run_command

pytestmark = [pytest.mark.integration, pytest.mark.environment]
ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def harness(tmp_path: Path) -> Path:
    """Copy only test infrastructure so probes cannot accidentally collect the real suites."""
    root = tmp_path / "harness"
    (root / "tests").mkdir(parents=True)
    shutil.copy2(ROOT / "pytest.ini", root)
    for name in ("__init__.py", "conftest.py", "catalogue.py", "case_reports.py",
                 "runtime_fixtures.py", "runtime_support.py"):
        shutil.copy2(ROOT / "tests" / name, root / "tests" / name)
    return root


def invoke(root: Path, source: str, *arguments: str, no_tools: bool = False) -> CommandResult:
    """Run a bounded isolated collection or execution using the same pinned pytest interpreter."""
    (root / "tests/test_probe.py").write_text(source)
    environment = dict(os.environ)
    environment["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    if no_tools:
        environment["PATH"] = str(root / "missing-tools")
    return run_command([sys.executable, "-m", "pytest", "-q", *arguments], cwd=root,
                       timeout=15, environment=environment)


def test_catalogue_needs_no_runtime_and_respects_selection(harness: Path) -> None:
    """Selected parameter IDs and marker metadata list without executing fixtures or creating reports."""
    source = '''import pytest
pytestmark = [pytest.mark.integration, pytest.mark.requires_lean]
@pytest.fixture(autouse=True)
def forbidden():
    raise AssertionError("fixture ran")
@pytest.mark.parametrize("value", [1, 2], ids=["first", "second"])
def test_selected(value):
    """A named variant must remain independently selectable."""
    assert value
'''
    result = invoke(harness, source, "--catalog", "--catalog-json", "catalog.json", "-k", "second", no_tools=True)
    assert result.returncode == 0, result.diagnostic()
    cases = json.loads((harness / "catalog.json").read_text())
    assert len(cases) == 1 and cases[0]["parameter_id"] == "second"
    assert cases[0]["resources"] == ["requires_lean"]
    assert not (harness / "build").exists()


@pytest.mark.parametrize("source,diagnostic", [
    ('import pytest\n@pytest.mark.unit\ndef test_bad(): pass\n', "Missing scenario description"),
    ('def test_bad():\n    """Missing level is rejected."""\n', "exactly one level"),
    ('import pytest\n@pytest.mark.unit\n@pytest.mark.e2e\ndef test_bad():\n    """Two levels are rejected."""\n', "exactly one level"),
    ('import pytest\n@pytest.mark.unknown\ndef test_bad():\n    """Unknown marker is rejected."""\n', "unknown"),
], ids=["description", "missing-level", "two-levels", "unknown-marker"])
def test_invalid_metadata_fails_collection(harness: Path, source: str, diagnostic: str) -> None:
    """Missing descriptions or invalid markers cannot silently enter the catalogue."""
    result = invoke(harness, source, "--catalog")
    assert result.returncode != 0 and diagnostic in result.stdout + result.stderr, result.diagnostic()


def test_duplicate_selected_ids_are_rejected(harness: Path) -> None:
    """Selecting the same node twice cannot overwrite its report or evidence."""
    source = 'import pytest\n@pytest.mark.unit\ndef test_same():\n    """Duplicate identities fail."""\n'
    result = invoke(harness, source, "--catalog", "--keep-duplicates", "tests/test_probe.py", "tests/test_probe.py")
    assert result.returncode != 0 and "Duplicate test node ID" in result.stdout + result.stderr, result.diagnostic()


def test_missing_tools_fail_setup_and_runtime_reports_are_separate(harness: Path) -> None:
    """Selected unavailable tools produce setup errors in separate source and installed artifacts."""
    source = 'import pytest\npytestmark = [pytest.mark.integration, pytest.mark.requires_lean]\ndef test_tool():\n    """Missing Lean must fail setup."""\n    raise AssertionError("call ran")\n'
    paths = []
    for runtime in ("source", "installed"):
        result = invoke(harness, source, "--runtime-variant", runtime, "--suite", "probe", no_tools=True)
        diagnostic = "Required Lean compiler is missing" if runtime == "source" else "Required runtime file is missing"
        assert result.returncode == 1 and diagnostic in result.stdout, result.diagnostic()
        report = json.loads((harness / f"build/test-results/{runtime}/probe.json").read_text())
        case = report["cases"][0]
        assert case["phases"]["setup"]["outcome"] == "failed" and "call" not in case["phases"]
        assert case["phases"]["setup"]["duration"] >= 0
        path = Path(case["failure_artifacts"])
        assert json.loads((path / "case.json").read_text())["runtime"] == runtime
        assert (harness / f"build/test-results/{runtime}/probe.xml").is_file()
        paths.append(path)
    assert paths[0] != paths[1] and all(path.is_dir() for path in paths)


def test_installed_missing_compiler_cannot_fall_back_to_host(harness: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Even with a working host Lean, an incomplete installed runtime fails during setup."""
    compiler = harness / "host/lean/bin/lean"
    compiler.parent.mkdir(parents=True)
    compiler.write_text(f'#!/bin/sh\nprintf "%s\\n" "{compiler.parents[1]}"\n')
    compiler.chmod(0o755)
    monkeypatch.setenv("PATH", str(compiler.parent) + os.pathsep + os.environ["PATH"])
    source = 'import pytest\npytestmark = [pytest.mark.integration,pytest.mark.requires_lean("compiler")]\ndef test_compiler():\n    """The selected compiler must exist."""\n    assert True\n'
    host = invoke(harness, source)
    assert host.returncode == 0, host.diagnostic()
    installed = invoke(harness, source, "--runtime-variant", "installed")
    assert installed.returncode == 1 and "Required runtime file is missing" in installed.stdout, installed.diagnostic()


def test_command_json_diagnostics_retain_both_streams(tmp_path: Path) -> None:
    """Malformed JSON retains the command, status, stdout, stderr and elapsed time."""
    result = run_command([sys.executable, "-c", "import sys; print('invalid'); print('detail',file=sys.stderr)"],
                         cwd=tmp_path, timeout=5)
    with pytest.raises(AssertionError) as failure:
        result.json_object()
    assert all(value in str(failure.value) for value in ("invalid", "detail", "elapsed", "returncode", sys.executable))


@pytest.mark.parametrize("scenario,phase", [("success", "call"), ("teardown", "teardown"),
                                             ("timeout", "call"), ("json", "call")])
def test_execution_reports_preserve_phase_outcomes(harness: Path, scenario: str, phase: str) -> None:
    """Successful phases and teardown, timeout or malformed-output failures retain machine diagnostics."""
    actions = {
        "success": "assert True",
        "teardown": "assert True",
        "timeout": "command_runner([sys.executable,'-c','import time; time.sleep(60)'],cwd=tmp_path,timeout=0.05)",
        "json": "command_runner([sys.executable,'-c',\"import sys; print('bad-json'); print('stderr detail',file=sys.stderr)\"],cwd=tmp_path,timeout=5).json_object()",
    }
    source = ('import pytest,sys\npytestmark = pytest.mark.unit\n'
              '@pytest.fixture(autouse=True)\ndef cleanup():\n    yield\n'
              + ('    raise AssertionError("teardown detail")\n' if scenario == "teardown" else '')
              + 'def test_probe(command_runner,tmp_path):\n    """Exercise a report phase."""\n    '
              + actions[scenario] + '\n')
    result = invoke(harness, source, "--suite", "phases")
    assert result.returncode == (0 if scenario == "success" else 1), result.diagnostic()
    case = json.loads((harness / "build/test-results/source/phases.json").read_text())["cases"][0]
    assert set(case["phases"]) == {"setup", "call", "teardown"}
    assert all(value["duration"] >= 0 for value in case["phases"].values())
    assert case["phases"][phase]["outcome"] == ("passed" if scenario == "success" else "failed")
    assert case["phases"]["call"]["timed_out"] == (scenario == "timeout")
    if scenario != "success":
        assert (Path(case["failure_artifacts"]) / f"{phase}.txt").is_file()
    if scenario == "json":
        assert "bad-json" in case["phases"]["call"]["diagnostic"]
        assert "stderr detail" in case["phases"]["call"]["diagnostic"]


def test_timeout_kills_descendants_and_retains_output(tmp_path: Path) -> None:
    """A timed-out process group is killed, its leader reaped, and partial diagnostics preserved."""
    program = ("import subprocess,sys,time\nfrom pathlib import Path\n"
               "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'])\n"
               "Path('child.pid').write_text(str(child.pid))\n"
               "print('partial stdout',flush=True)\nprint('partial stderr',file=sys.stderr,flush=True)\n"
               "child.wait()\n")
    with pytest.raises(CommandTimeout) as failure:
        run_command([sys.executable, "-c", program], cwd=tmp_path, timeout=1, artifacts=tmp_path / "evidence")
    result = failure.value.result
    assert result.timed_out and result.returncode != 0
    assert "partial stdout" in result.stdout and "partial stderr" in result.stderr
    assert (tmp_path / "evidence/command-0000.json").is_file()
    pid = int((tmp_path / "child.pid").read_text())
    # A dead orphan may briefly remain as a zombie until the host's init reaps it.
    for _ in range(50):
        status = run_command(["/bin/ps", "-o", "stat=", "-p", str(pid)], cwd=tmp_path, timeout=2)
        if not status.stdout.strip() or status.stdout.strip().startswith("Z"):
            break
        time.sleep(0.02)
    else:
        pytest.fail(f"Child {pid} survived process-group timeout cleanup")
