"""Fast boundary regressions for installed loader metadata and exclusive installation ownership."""

import importlib.util
import os
import shutil
import subprocess
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class InstalledRuntimeTests(unittest.TestCase):
    """A trusted installation still rejects overbroad roots and preserves another installer's files."""

    def test_deleted_modules_are_not_packaged(self) -> None:
        """A stale compiled module must stay out of the archive after source deletion."""
        sys.path.insert(0, str(ROOT / "packaging"))
        from build_runtime import copy_runtime, project_runtime_files
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "SqliteVerifier").mkdir()
            (root / "SqliteVerifier/Current.lean").write_text("-- current source\n")
            library = root / ".lake/build/lib/lean"
            (library / "SqliteVerifier").mkdir(parents=True)
            for name in ("Current.olean", "Current.olean.private", "Current.ir", "Removed.olean"):
                (library / "SqliteVerifier" / name).write_text("fixture")
            destination = root / "packaged"
            copy_runtime(library, destination, project_runtime_files(root))
            self.assertEqual(sorted(path.name for path in destination.rglob("*") if path.is_file()),
                             ["Current.ir", "Current.olean", "Current.olean.private"])
            (root / "SqliteVerifier/Unbuilt.lean").write_text("-- not built\n")
            with self.assertRaisesRegex(ValueError, "not been built"):
                project_runtime_files(root)

    def test_installer_cache_uri(self) -> None:
        """Extraction directories with spaces, Unicode and URI delimiters remain literal paths."""
        with TemporaryDirectory(prefix="installer URI % # ü ") as temporary:
            bundle = Path(temporary).resolve()
            (bundle / "nix-cache").mkdir()
            (bundle / "nix-cache/nix-cache-info").write_text("StoreDir: /nix/store\n")
            (bundle / "payload").mkdir()
            (bundle / "payload/marker").write_text("installed")
            (bundle / "nix-paths").write_text("")
            (bundle / "python-path").write_text(sys.executable + "\n")
            import platform
            system = "aarch64-darwin" if platform.system() == "Darwin" else "x86_64-linux"
            (bundle / "platform").write_text(system + "\n")
            for name in ("install.sh", "install.py"):
                shutil.copy2(ROOT / "packaging" / name, bundle / name)
            destination = bundle / "installation"
            result = subprocess.run([str(bundle / "install.sh"), str(destination)],
                                    env=dict(os.environ), capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((destination / "marker").read_text(), "installed")

    def test_install_does_not_delete_concurrent_destination(self) -> None:
        """Failure to acquire the destination must never authorize cleaning that directory."""
        specification = importlib.util.spec_from_file_location("bundle_installer", ROOT / "packaging/install.py")
        assert specification is not None and specification.loader is not None
        installer = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(installer)
        with TemporaryDirectory() as temporary:
            bundle = Path(temporary)
            (bundle / "nix-paths").write_text("")
            destination = bundle / "destination"
            original_mkdir = Path.mkdir

            def concurrent_mkdir(path: Path, *arguments: object, **keywords: object) -> None:
                """Simulate another installer winning between existence test and exclusive creation."""
                if path == destination:
                    original_mkdir(path)
                    (path / "unrelated.txt").write_text("keep")
                    raise FileExistsError(path)
                original_mkdir(path, *arguments, **keywords)

            with patch.object(installer, "__file__", str(bundle / "install.py")), patch.object(Path, "mkdir", concurrent_mkdir):
                with self.assertRaises(FileExistsError):
                    installer.install(destination)
            self.assertEqual((destination / "unrelated.txt").read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
