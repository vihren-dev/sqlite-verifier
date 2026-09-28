"""Exercise the source orchestrator with real tiny pytest children and evidence aggregation."""

import json
from pathlib import Path
import textwrap

import pytest

from tools import run_source_suite

pytestmark = [pytest.mark.integration, pytest.mark.environment]


@pytest.mark.parametrize("failure", [False, True], ids=["success", "failed-suite"])
def test_source_runner_once(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, failure: bool) -> None:
    """All source children share a UUID/runtime and aggregate after each case executes once."""
    root = tmp_path.resolve()
    monkeypatch.chdir(root)
    monkeypatch.setattr(run_source_suite, "ROOT", root)
    monkeypatch.delenv("SQLITE_VERIFIER_UNIT_CHECKS", raising=False)
    monkeypatch.setenv("SQLITE_VERIFIER_RUNTIME_ROOT", str(root / "immutable-runtime"))
    (root / "tests").mkdir()
    (root / "conformance").mkdir()
    (root / "pytest.ini").write_text("[pytest]\npython_files = test_*.py *_test.py\n")
    (root / "conftest.py").write_text(textwrap.dedent('''
        import json
        from pathlib import Path
        def pytest_addoption(parser):
            for name in ('catalog-json', 'runtime-root', 'runtime-variant', 'run-id', 'suite', 'report-dir'):
                parser.addoption('--' + name)
        def pytest_configure(config):
            if config.getoption('catalog_json'):
                config.option.collectonly = True
        def pytest_collection_finish(session):
            path = session.config.getoption('catalog_json')
            if path:
                Path(path).write_text(json.dumps([{'node_id': item.nodeid} for item in session.items]))
        def pytest_sessionfinish(session):
            config = session.config
            if not config.getoption('catalog_json'):
                reports = Path(config.getoption('report_dir')) / 'source'
                reports.mkdir(parents=True, exist_ok=True)
                for suffix, content in (('json', '{}'), ('xml', '<testsuites/>')):
                    (reports / (config.getoption('suite') + '.' + suffix)).write_text(content)
                path = Path('invocations.jsonl')
                with path.open('a') as stream:
                    stream.write(json.dumps({'run': config.getoption('run_id'),
                        'runtime': config.getoption('runtime_root'),
                        'suite': config.getoption('suite')}) + '\\n')
    '''))
    scripts = ["kernel_gate_test.py", "cli_test.py", "atuin_cli_test.py", "test_profiles.py"]
    for script in scripts:
        (root / "tests" / script).write_text(
            "from pathlib import Path\ndef test_once():\n"
            f"    path = Path({script!r} + '.count')\n"
            "    assert not path.exists()\n    path.write_text('1')\n"
            + ("    assert False, 'case failed'\n" if failure and script == "cli_test.py" else ""))
    (root / "tests/runtime_package_test.py").write_text("raise AssertionError('installed was selected')\n")
    (root / "conformance/coverage_report.py").write_text(textwrap.dedent('''
        import argparse, json
        from pathlib import Path
        parser = argparse.ArgumentParser()
        for name in ('run-id', 'reports', 'runtime-root', 'output'):
            parser.add_argument('--' + name)
        args = parser.parse_args()
        runs = [json.loads(line) for line in Path('invocations.jsonl').read_text().splitlines()]
        assert len(runs) == 4
        assert {row['run'] for row in runs} == {args.run_id}
        assert {row['runtime'] for row in runs} == {args.runtime_root}
        assert args.reports == 'build/test-results/source'
        Path(args.output).write_text(json.dumps({'run_id': args.run_id, 'status': 'EVIDENCE_CHECKS_PASSED'}))
    '''))
    (root / "build").mkdir()
    (root / "build/coverage.json").write_text('{"stale": true}')
    assert run_source_suite.main() == int(failure)
    assert len(list(root.glob("*.count"))) == len(scripts)
    report = json.loads((root / "build/coverage.json").read_text())
    from uuid import UUID
    assert str(UUID(report["run_id"])) == report["run_id"]
