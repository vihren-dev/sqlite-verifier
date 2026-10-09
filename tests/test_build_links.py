"""`just build` links the Lean outputs of every Lake package into the checkout.

Tests that use the checkout as their runtime root read each package's compiled
modules at `PACKAGE/.lake/build` (see `tests/runtime_fixtures.py`). Lake builds a
path dependency in its own directory, so each package needs its own link to the
built runtime. Without the link of a new package, those tests fail with a missing
module file although the runtime has it.
"""

from pathlib import Path
import shlex
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.mark.requires_native("just")
def test_build_links_each_lake_package_output_to_the_runtime() -> None:
    """Each directory with a lakefile.toml gets a `.lake/build` link into `build/runtime`."""
    result = subprocess.run(["just", "--dry-run", "build"], cwd=ROOT, capture_output=True,
                            text=True, timeout=5)
    assert result.returncode == 0, result.stdout + result.stderr
    links: dict[Path, Path] = {}
    for line in (result.stdout + result.stderr).splitlines():
        words = shlex.split(line)
        if words[:2] == ["ln", "-sfn"]:
            link = ROOT / words[3]
            links[link] = (link.parent / words[2]).resolve(strict=False)
    packages = [lakefile.parent for lakefile in [ROOT / "lakefile.toml",
                                                 *(ROOT / "packages").glob("*/lakefile.toml")]]
    assert len(packages) >= 2
    for package in packages:
        relative = package.relative_to(ROOT)
        link = package / ".lake/build"
        assert link in links, f"just build does not link {relative / '.lake/build'}"
        assert links[link] == (ROOT / "build/runtime" / relative / ".lake/build").resolve(strict=False)
