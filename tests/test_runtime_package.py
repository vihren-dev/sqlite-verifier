"""Fast boundary regressions for the offline installer's paths and exclusive destination ownership."""

import importlib.util
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.packaging


@pytest.mark.integration
@pytest.mark.requires_nix
def test_installer_accepts_uri_special_bundle_path(tmp_path_factory: pytest.TempPathFactory) -> None:
    """A bundle extracted under spaces, Unicode, `%` and `#` installs from its local Nix cache."""
    bundle = tmp_path_factory.mktemp("installer URI % # ü ").resolve()
    (bundle / "nix-cache").mkdir()
    (bundle / "nix-cache/nix-cache-info").write_text("StoreDir: /nix/store\n")
    (bundle / "runtime").mkdir()
    (bundle / "runtime/marker").write_text("installed")
    runtime = subprocess.run(["nix-store", "--add", str(bundle / "runtime")],
                             check=True, capture_output=True, text=True, timeout=15).stdout.strip()
    (bundle / "runtime-path").write_text(runtime + "\n")
    (bundle / "nix-paths").write_text(runtime + "\n")
    (bundle / "python-path").write_text(sys.executable + "\n")
    system = "aarch64-darwin" if platform.system() == "Darwin" else "x86_64-linux"
    (bundle / "platform").write_text(system + "\n")
    for name in ("install.sh", "install.py"):
        shutil.copy2(ROOT / "packaging" / name, bundle / name)
    destination = bundle / "installation"
    result = subprocess.run([str(bundle / "install.sh"), str(destination)],
                            env=dict(os.environ), capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (destination / "marker").read_text() == "installed"


@pytest.mark.unit
def test_install_does_not_delete_concurrent_destination(tmp_path: Path) -> None:
    """Failure to acquire the destination must never authorize cleaning that directory."""
    specification = importlib.util.spec_from_file_location("bundle_installer", ROOT / "packaging/install.py")
    assert specification is not None and specification.loader is not None
    installer = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(installer)
    runtime = Path("/nix/store/" + "0" * 32 + "-runtime")
    (tmp_path / "nix-paths").write_text(str(runtime) + "\n")
    (tmp_path / "runtime-path").write_text(str(runtime) + "\n")
    destination = tmp_path / "destination"
    original_mkdir = Path.mkdir
    original_resolve = Path.resolve

    def resolve(path: Path, *args: object, **kwargs: object) -> Path:
        """Supply the immutable fixture root without requiring a real Nix store."""
        return path if path == runtime else original_resolve(path, *args, **kwargs)

    def concurrent_mkdir(path: Path, *arguments: object, **keywords: object) -> None:
        """Simulate another installer winning between existence test and exclusive creation."""
        if path == destination:
            original_mkdir(path)
            (path / "unrelated.txt").write_text("keep")
            raise FileExistsError(path)
        original_mkdir(path, *arguments, **keywords)

    with patch.object(installer, "__file__", str(tmp_path / "install.py")), \
         patch.object(Path, "mkdir", concurrent_mkdir), patch.object(Path, "resolve", resolve):
        with pytest.raises(FileExistsError):
            installer.install(destination)
    assert (destination / "unrelated.txt").read_text() == "keep"
