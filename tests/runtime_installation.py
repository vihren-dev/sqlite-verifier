"""Install a real archive once; every acceptance case uses its isolated public entrypoint."""

from pathlib import Path
import shutil
import tarfile

import pytest

from tests.case_reports import REPORTS
from tests.runtime_support import run_command


@pytest.fixture(scope="session")
def installed_runtime(pytestconfig: pytest.Config, tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Extract safely and install offline into a fresh path with spaces, Unicode and URI bytes."""
    archive = pytestconfig.getoption("runtime_archive")
    if archive is None or not archive.is_file():
        pytest.fail(f"A built archive is required: --runtime-archive PATH (received {archive})")
    nix = shutil.which("nix")
    if nix is None:
        pytest.fail("Nix is required to install the runtime archive")
    root = tmp_path_factory.mktemp("runtime package % # ü ").resolve()
    extraction = root / "extracted archive"
    extraction.mkdir()
    with tarfile.open(archive.resolve()) as contents:
        contents.extractall(extraction, filter="data")
    bundles = list(extraction.iterdir())
    if len(bundles) != 1 or not bundles[0].is_dir():
        pytest.fail("Runtime archive must contain exactly one bundle directory")
    destination = root / "installed verifier % # ü"
    environment = {"HOME": str(root), "LANG": "C.UTF-8",
                   "PATH": f"{Path(nix).absolute().parent}:/usr/bin:/bin"}
    reports = pytestconfig.stash[REPORTS]
    artifacts = reports.artifacts("session::offline_runtime_installation")
    reports.shared_artifacts["offline_installation"] = str(artifacts)
    result = run_command([str(bundles[0] / "install.sh"), str(destination)], cwd=root,
                         environment=environment, timeout=300, artifacts=artifacts)
    assert result.returncode == 0, result.diagnostic()
    return destination
