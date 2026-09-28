"""Repository pytest options, isolated examples and execution-only runtime fixtures."""

from collections.abc import Callable, Generator, Mapping, Sequence
import json
import os
from pathlib import Path
import re
import subprocess
from uuid import uuid4

import pytest

from tests.case_reports import REPORTS, RunReports
from tests.catalogue import describe_cases
from tests.runtime_support import CommandResult, CommandTimeout, copy_mutable_tree, run_command

pytest_plugins = ["tests.runtime_fixtures", "tests.runtime_installation"]


@pytest.hookimpl(tryfirst=True)
def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    """Keep the docs-only stdlib checks runnable without importing pytest or entering Nix."""
    pure = {
        "tests/docs_test.py::test_local_markdown_links",
        "tests/test_ci_scope.py::CiScopeTest::test_change_scopes",
        "tests/test_ci_scope.py::CiScopeTest::test_release_and_manual_runs_package",
        "tests/test_ci_scope.py::CiScopeTest::test_documentation_links",
    }
    for item in items:
        if item.nodeid in pure:
            item.add_marker(pytest.mark.unit)
        elif item.nodeid == "tests/test_ci_scope.py::CiScopeTest::test_real_diff_preserves_removed_runtime_paths":
            item.add_marker(pytest.mark.integration)
            item.add_marker(pytest.mark.approval)
            item.add_marker(pytest.mark.requires_native("git"))


def pytest_addoption(parser: pytest.Parser) -> None:
    """Expose collection, runtime and report selection without introducing another runner."""
    group = parser.getgroup("sqlite-verifier")
    group.addoption("--catalog", action="store_true", help="List selected cases without executing")
    group.addoption("--catalog-json", type=Path, help="Write selected case metadata without executing")
    group.addoption("--runtime-root", type=Path, help="Built executable and examples root")
    group.addoption("--runtime-archive", type=Path, help="Archive to install once for installed cases")
    group.addoption("--runtime-variant", choices=("source", "installed"), default="source")
    group.addoption("--report-dir", type=Path, default=Path("build/test-results"))
    group.addoption("--suite", default="selected", help="Report basename within the runtime directory")
    group.addoption("--run-id", default=None, help="Shared fresh invocation identity for aggregate evidence")


@pytest.hookimpl(tryfirst=True)
def pytest_configure(config: pytest.Config) -> None:
    """Prepare report paths in memory; collection cannot create runtime or report artifacts."""
    if config.getoption("catalog") or config.getoption("catalog_json"):
        config.option.collectonly = True
    if config.getoption("runtime_archive") is not None:
        if config.getoption("runtime_root") is not None or config.getoption("runtime_variant") != "installed":
            raise pytest.UsageError("--runtime-archive requires --runtime-variant installed and no --runtime-root")
    suite = config.getoption("suite")
    if re.fullmatch(r"[A-Za-z0-9_-]+", suite) is None:
        raise pytest.UsageError("--suite must contain only letters, digits, underscore or hyphen")
    directory = config.getoption("report_dir").absolute()
    runtime = config.getoption("runtime_variant")
    run_id = config.getoption("run_id") or uuid4().hex
    if re.fullmatch(r"[A-Za-z0-9_-]+", run_id) is None:
        raise pytest.UsageError("--run-id must contain only letters, digits, underscore or hyphen")
    config.stash[REPORTS] = RunReports(directory, runtime, suite, run_id)
    if not config.option.collectonly and not config.option.xmlpath:
        config.option.xmlpath = str(directory / runtime / f"{suite}.xml")


@pytest.hookimpl(trylast=True)
def pytest_collection_finish(session: pytest.Session) -> None:
    """Validate actual selected node IDs after pytest has applied -m/-k/path filters."""
    cases = describe_cases(session.items)
    session.config.stash[REPORTS].cases = cases
    if not session.config.option.collectonly:
        session.config.stash[REPORTS].checkpoint_selection()
    destination = session.config.getoption("catalog_json")
    if destination is not None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(cases, indent=2) + "\n")
    if session.config.getoption("catalog"):
        reporter = session.config.pluginmanager.getplugin("terminalreporter")
        if reporter is not None:
            for case in cases:
                reporter.write_line(json.dumps(case, ensure_ascii=False))


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(item: pytest.Item, call: pytest.CallInfo[None]) -> Generator[None, pytest.TestReport, pytest.TestReport]:
    """Observe final reports after pytest constructs assertion and fixture diagnostics."""
    report = yield
    timed_out = call.excinfo is not None and isinstance(call.excinfo.value, (CommandTimeout, subprocess.TimeoutExpired))
    item.config.stash[REPORTS].observe(report, timed_out=timed_out)
    return report


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    """Always retain execution summaries, including setup failures; never during listing."""
    if not session.config.option.collectonly:
        session.config.stash[REPORTS].write(int(exitstatus))


@pytest.fixture(scope="session")
def runtime_root(pytestconfig: pytest.Config, request: pytest.FixtureRequest) -> Path:
    """Resolve the selected artifact root lazily, without checking unrelated prerequisites."""
    if pytestconfig.getoption("runtime_archive") is not None:
        return request.getfixturevalue("installed_runtime")
    root = pytestconfig.getoption("runtime_root") or pytestconfig.rootpath
    if not root.is_dir():
        pytest.fail(f"Runtime directory is missing: {root}; build the selected runtime first")
    return root.resolve()


@pytest.fixture
def example_factory(runtime_root: Path, tmp_path: Path) -> Callable[[str], Path]:
    """Give each requested example an independent mutable copy, preserving all relative paths."""
    def copy_example(name: str) -> Path:
        """Copy only examples under the selected runtime, using a distinct directory each time."""
        source = (runtime_root / "examples" / name).resolve(strict=True)
        if not source.is_relative_to(runtime_root / "examples"):
            raise ValueError(f"Example escapes selected runtime: {name}")
        destination = tmp_path / f"example-{len(list(tmp_path.glob('example-*')))}"
        return copy_mutable_tree(source, destination)
    return copy_example


@pytest.fixture
def runtime_environment(pytestconfig: pytest.Config, tmp_path: Path) -> dict[str, str]:
    """Poison only installed children, leaving the dev pytest interpreter and parent untouched."""
    if pytestconfig.getoption("runtime_variant") == "source":
        return dict(os.environ)
    poison = tmp_path / "ambient imports"
    poison.mkdir()
    (poison / "json.py").write_text('raise RuntimeError("ambient Python imported")\n')
    return {"HOME": str(tmp_path), "LANG": "C.UTF-8", "PATH": "/usr/bin:/bin",
            "PYTHONPATH": str(poison), "LEAN_PATH": str(poison),
            "MIGRATION_CHECK_LEAN_SYSROOT": str(poison)}


@pytest.fixture
def case_artifacts(request: pytest.FixtureRequest) -> Path:
    """Retain command observations under this case's complete runtime-qualified identity."""
    return request.config.stash[REPORTS].artifacts(request.node.nodeid)


@pytest.fixture
def command_runner(runtime_environment: dict[str, str], case_artifacts: Path) -> Callable[..., CommandResult]:
    """Bind the per-case child environment and evidence directory to the bounded runner."""
    def invoke(arguments: Sequence[str], *, cwd: Path, timeout: float,
               environment: Mapping[str, str] | None = None) -> CommandResult:
        """Allow source-internal fixtures to supply explicit Lean paths without changing defaults."""
        return run_command(arguments, cwd=cwd, timeout=timeout, artifacts=case_artifacts,
                           environment=runtime_environment if environment is None else environment)
    return invoke
