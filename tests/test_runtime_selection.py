"""Test archive selection and receipt freshness without building or installing an archive."""

import json
from pathlib import Path

import pytest

from tests.test_pytest_harness import harness, invoke

pytestmark = [pytest.mark.integration, pytest.mark.environment]
PROBE = ('import pytest\npytestmark=pytest.mark.integration\n'
         'def test_root(runtime_root):\n    """Resolve only during execution."""\n'
         '    assert runtime_root.is_dir()\n')


def test_archive_collection_defers_installation(harness: Path) -> None:
    """An absent archive lists without Nix; executing that selected case reports setup failure."""
    options = ("--runtime-variant", "installed", "--runtime-archive", "absent.tar.gz")
    collected = invoke(harness, PROBE, *options, "--catalog", no_tools=True)
    assert collected.returncode == 0 and not (harness / "build").exists(), collected.diagnostic()
    executed = invoke(harness, PROBE, *options, no_tools=True)
    assert executed.returncode == 1 and "A built archive is required" in executed.stdout, executed.diagnostic()
    report = json.loads((harness / "build/test-results/installed/selected.json").read_text())
    assert report["cases"][0]["phases"]["setup"]["outcome"] == "failed"


@pytest.mark.parametrize("options", [[], ["--runtime-variant", "installed", "--runtime-root", "."]],
                         ids=["source-variant", "conflicting-root"])
def test_archive_rejects_ambiguous_runtime(harness: Path, options: list[str]) -> None:
    """An archive cannot be labeled source evidence or combined with a different executable root."""
    result = invoke(harness, PROBE, "--runtime-archive", "absent.tar.gz", *options, "--catalog")
    assert result.returncode != 0 and "--runtime-archive requires" in result.stderr, result.diagnostic()


def test_repeated_case_cannot_reuse_old_receipt(harness: Path) -> None:
    """A later failing invocation has a distinct receipt directory even for the same case and suite."""
    prefix = ('import pytest\npytestmark=pytest.mark.integration\n'
              'def test_receipt(case_artifacts):\n    """Keep evidence invocation-specific."""\n')
    paths = []
    for action, code in [('(case_artifacts/"receipt.json").write_text("passed")', 0), ('assert False', 1)]:
        result = invoke(harness, prefix + '    ' + action + '\n')
        assert result.returncode == code, result.diagnostic()
        report = json.loads((harness / "build/test-results/source/selected.json").read_text())
        case = report["cases"][0]
        path = Path(case["artifacts"])
        assert json.loads((path / "case.json").read_text())["run_id"] == report["run_id"]
        paths.append(path)
    assert paths[0] != paths[1]
    assert (paths[0] / "receipt.json").is_file() and not (paths[1] / "receipt.json").exists()
