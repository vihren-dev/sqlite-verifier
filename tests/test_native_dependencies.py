"""Regress Linux loader discovery without requiring Linux binaries on every test host."""

import importlib.util
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class NativeDependenciesTest(unittest.TestCase):
    """Patched ELF interpreters need exact store roots, even when bundled libraries suffice."""

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

    def test_linux_loader_and_library_paths(self) -> None:
        """Preserve the interpreter root and bundled symlinks; reject missing/foreign libraries."""
        specification = importlib.util.spec_from_file_location(
            "native_dependencies_under_test", ROOT / "packaging/runtime_dependencies.py")
        assert specification is not None and specification.loader is not None
        collector = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(collector)
        with TemporaryDirectory() as temporary:
            lean = Path(temporary).resolve()
            (lean / "bin").mkdir()
            (lean / "lib").mkdir()
            executable = lean / "bin/lean"
            executable.touch()
            bundled = lean / "lib/libleanshared.so.1"
            bundled.write_bytes(b"\x7fELF" + b"versioned shared object fixture")
            linker_script = lean / "lib/libc++.so"
            linker_script.write_text("INPUT(libc++.so.1 -lunwind)\n", encoding="utf-8")
            alias = lean / "lib/libleanshared.so"
            alias.symlink_to(bundled.name)
            module = lean / "lib/lean/Lean/Nested.so"
            module.parent.mkdir(parents=True)
            module.write_bytes(b"\x7fELFmodule")
            for compiler_directory in ("glibc", "clang", "libc"):
                sdk = lean / "lib" / compiler_directory / "sdk.so"
                sdk.parent.mkdir()
                sdk.write_bytes(b"\x7fELFcompiler sysroot, not an interpreter library")
            private_object = module.with_suffix(".olean.private")
            private_object.write_bytes(b"complete import surface")
            ir = module.with_suffix(".ir")
            ir.write_bytes(b"interpreter IR")
            self.assertEqual(set(collector.lean_runtime_files(lean)),
                             {bundled, alias, linker_script, module, private_object, ir})
            loader = Path("/nix/store/00000000000000000000000000000000-glibc/lib/ld-linux-x86-64.so.2")
            store = loader.parent.parent
            report = ("linux-vdso.so.1 (0x0001)\n"
                      f"libleanshared.so => {alias} (0x0002)\n"
                      f"{loader} (0x0003)\n"
                      "/lib/x86_64-linux-gnu/libc.so.6 (0x0004)\n")
            with patch.object(collector.platform, "system", return_value="Linux"), \
                    patch.object(collector, "run", return_value=report) as run, \
                    patch.object(collector, "store_path", return_value=store) as store_path:
                roots, reports = collector.native_dependencies([executable], lean)
                self.assertEqual(roots, {store})
                self.assertNotIn(Path("/nix/store"), roots)
                self.assertIn(str(loader), reports)
                self.assertIn(f"Binary: {executable}\n", reports)
                self.assertEqual({Path(call.args[0][1]) for call in run.call_args_list},
                                 {executable, bundled, alias, module})
                self.assertTrue(all(call.args[0][0] == "ldd" for call in run.call_args_list))
                self.assertTrue(all(call.args == (loader,) for call in store_path.call_args_list))
            package_spec = importlib.util.spec_from_file_location(
                "build_runtime_under_test", ROOT / "packaging/build_runtime.py")
            assert package_spec is not None and package_spec.loader is not None
            package = importlib.util.module_from_spec(package_spec)
            with patch.dict(sys.modules, {"runtime_dependencies": collector}):
                package_spec.loader.exec_module(package)
            destination = lean / "copied"
            package.copy_runtime(lean / "lib", destination, collector.lean_runtime_files(lean))
            self.assertEqual({path.relative_to(destination) for path in destination.rglob("*") if path.is_file()},
                             {path.relative_to(lean / "lib") for path in collector.lean_runtime_files(lean)})
            for failure, diagnostic in (("libLean.so => not found", "Unresolved"),
                                        ("/home/runner/private/lib.so (0x1234)", "Nonportable"),
                                        (f"{lean}/lib/glibc/sdk.so (0x1234)", "Nonportable")):
                with patch.object(collector.platform, "system", return_value="Linux"), \
                        patch.object(collector, "run", return_value=failure):
                    with self.assertRaisesRegex(RuntimeError, diagnostic):
                        collector.native_dependencies([executable], lean)

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
