"""Exercise real OS isolation rather than checking only generated command strings."""

from pathlib import Path
import platform
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
import time

from migration_check.sandbox import run_sandboxed, sandbox_command


class SandboxTest(unittest.TestCase):
    """A proof process can read inputs/write outputs but cannot alter its context."""

    def test_isolation_and_timeout(self) -> None:
        """Check writes, private reads, networking, credentials, and bounded execution."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            inputs = root / "inputs"
            outputs = root / "outputs"
            inputs.mkdir()
            outputs.mkdir()
            protected = inputs / "approved.txt"
            protected.write_text("approved", encoding="utf-8")
            private = root / "private.txt"
            private.write_text("secret", encoding="utf-8")
            program = inputs / "check.py"
            program.write_text(
                "import os, pathlib, socket\n"
                f"protected = pathlib.Path({str(protected)!r})\n"
                "assert protected.read_text() == 'approved'\n"
                "try:\n protected.write_text('changed')\n"
                "except OSError as error:\n assert error.errno in (1, 13, 30), repr(error)\n"
                "else:\n raise AssertionError('wrote approved input')\n"
                f"private = pathlib.Path({str(private)!r})\n"
                "try:\n private.read_text()\n"
                "except (PermissionError, FileNotFoundError):\n pass\n"
                "else:\n raise AssertionError('read private data')\n"
                "try:\n socket.socket().connect(('127.0.0.1', 9))\n"
                "except OSError as error:\n"
                " assert error.errno in (1, 13, 101, 113), repr(error)\n"
                "else:\n raise AssertionError('network access allowed')\n"
                "assert 'GITHUB_TOKEN' not in os.environ\n"
                "pathlib.Path('result.txt').write_text('isolated')\n",
                encoding="utf-8",
            )
            executable = Path(sys.executable).resolve()
            runtime = Path(sys.base_prefix).resolve()
            roots = [inputs, runtime, executable.parent]
            if Path("/nix/store").exists():
                roots.append(Path("/nix/store"))
            for system_root in ("/usr/lib", "/lib", "/lib64"):
                if Path(system_root).exists():
                    roots.append(Path(system_root))
            result = run_sandboxed(
                [str(executable), "-I", str(program)], read_roots=roots,
                write_root=outputs, environment={}, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(protected.read_text(), "approved")
            self.assertEqual((outputs / "result.txt").read_text(), "isolated")
            with self.assertRaises(ValueError):
                sandbox_command([str(executable)], [root], outputs)
            with self.assertRaises(ValueError):
                sandbox_command([str(executable)], [inputs], root)
            with self.assertRaises(ValueError):
                run_sandboxed(
                    [str(executable)], read_roots=roots, write_root=outputs,
                    environment={"PYTHONPATH": str(inputs)},
                )
            noisy = run_sandboxed(
                [str(executable), "-I", "-c", "import sys; sys.stdout.write('x' * 20_000_000)"],
                read_roots=roots, write_root=outputs, environment={}, timeout=5,
            )
            self.assertNotEqual(noisy.returncode, 0)
            self.assertEqual(len(noisy.stdout), 1024 * 1024)
            with self.assertRaises(subprocess.TimeoutExpired):
                run_sandboxed(
                    [str(executable), "-I", "-c", "while True: pass"],
                    read_roots=roots, write_root=outputs, environment={}, timeout=0.5,
                )
            if platform.system() == "Darwin":
                fork_check = run_sandboxed(
                    [str(executable), "-I", "-c",
                     "import os\ntry:\n os.fork()\nexcept PermissionError:\n pass\n"
                     "else:\n raise AssertionError('fork permitted')"],
                    read_roots=roots, write_root=outputs, environment={}, timeout=5,
                )
                self.assertEqual(fork_check.returncode, 0, fork_check.stderr)
            else:
                with self.assertRaises(subprocess.TimeoutExpired):
                    run_sandboxed(
                        [str(executable), "-I", "-c",
                         "import os, pathlib, time\nif os.fork() == 0:\n"
                         " os.setsid()\n pathlib.Path('forked').touch()\n"
                         " time.sleep(4)\n pathlib.Path('leaked').touch()\n"
                         "else:\n time.sleep(60)"],
                        read_roots=roots, write_root=outputs, environment={}, timeout=3,
                    )
                self.assertTrue((outputs / "forked").exists())
                time.sleep(2)
                self.assertFalse((outputs / "leaked").exists())


if __name__ == "__main__":
    unittest.main()
