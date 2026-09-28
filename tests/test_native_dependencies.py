"""Restrict proof-process access to exact build-owned Nix closure paths."""

import pytest

import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class NativeDependenciesTest(unittest.TestCase):
    """Patched ELF interpreters need exact store roots, even when bundled libraries suffice."""

    @pytest.mark.integration
    @pytest.mark.packaging
    @pytest.mark.environment
    @pytest.mark.requires_nix
    def test_loader_roots(self) -> None:
        """Only exact existing Nix store entries can enter the proof-process read policy."""
        from migration_check.runtime import native_runtime_roots

        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assertEqual(native_runtime_roots(directory), [])
            metadata = directory / "nix-runtime-roots"
            for invalid in ("/", "/nix", "/nix/store", str(directory), "/nix/store/.links"):
                metadata.write_text(invalid + "\n")
                with self.assertRaises(ValueError):
                    native_runtime_roots(directory)
            executable = Path(sys.executable).resolve()
            self.assertEqual(executable.parts[:3], ("/", "nix", "store"), "Run in pinned Nix shell")
            expected = Path(*executable.parts[:4])
            metadata.write_text(str(expected) + "\n")
            self.assertEqual(native_runtime_roots(directory), [expected])

    @pytest.mark.integration
    @pytest.mark.packaging
    @pytest.mark.environment
    @pytest.mark.requires_nix
    def test_development_loader_roots_reach_both_sandboxes(self) -> None:
        """The build-owned manifest supplies loader roots to compilation and kernel checking."""
        from migration_check.runtime import Runtime, native_runtime_roots
        from migration_check.source_closure import lean_process

        executable = Path(sys.executable).resolve()
        self.assertEqual(executable.parts[:3], ("/", "nix", "store"), "Run in pinned Nix shell")
        store = Path(*executable.parts[:4])
        with TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            sysroot = root / "lean"
            library = root / ".lake/build/lib/lean"
            library.mkdir(parents=True)
            sysroot.mkdir()
            (root / "build").mkdir()
            (root / "build/nix-runtime-roots").write_text(str(store) + "\n", encoding="utf-8")
            self.assertEqual(native_runtime_roots(sysroot, library), [store])
            self.assertEqual(native_runtime_roots(sysroot, root / "unrelated"), [])
            runtime = Runtime(root, sysroot, library, root / "build/parser", root / ".lake/build/bin/checker")
            self.assertIn(store, runtime.read_roots())
            completed = subprocess.CompletedProcess([], 0, "header result", "")
            with patch("migration_check.source_closure.run_sandboxed", return_value=completed) as run:
                self.assertEqual(lean_process(sysroot, library, [], root / "Input.lean", root / "scratch",
                                              ["--deps-json"], "dependencies", timeout=5), "header result")
                self.assertIn(store, run.call_args.kwargs["read_roots"])
                self.assertNotIn(Path("/nix/store"), run.call_args.kwargs["read_roots"])
            # Installed manifests take precedence over the development fallback.
            (sysroot / "nix-runtime-roots").write_text("", encoding="utf-8")
            self.assertEqual(native_runtime_roots(sysroot, library), [])


if __name__ == "__main__":
    unittest.main()
