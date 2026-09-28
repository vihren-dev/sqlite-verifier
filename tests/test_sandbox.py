"""Select OS isolation, input guards, output limits and process cleanup independently."""

from pathlib import Path
import os
import platform
import socket
import subprocess
import sys
import time

import pytest

from migration_check.sandbox import run_sandboxed, sandbox_command

pytestmark = pytest.mark.environment


@pytest.fixture
def sandbox_paths(tmp_path: Path) -> tuple[Path, Path, Path, list[Path]]:
    """Allocate disjoint input/output trees and only the interpreter's required read roots."""
    root = tmp_path.resolve()
    inputs, outputs = root / "inputs", root / "outputs"
    inputs.mkdir()
    outputs.mkdir()
    # The pytest-bearing Nix wrapper execs another path; exercise the bare child interpreter.
    executable = Path(os.environ.get("SQLITE_VERIFIER_PYTHON", sys.executable)).resolve()
    roots = [inputs, Path(sys.base_prefix).resolve(), executable.parent]
    roots.extend(Path(path) for path in ("/nix/store", "/usr/lib", "/lib", "/lib64") if Path(path).exists())
    return executable, inputs, outputs, roots


@pytest.mark.integration
@pytest.mark.requires_sandbox
def test_isolation(sandbox_paths: tuple[Path, Path, Path, list[Path]]) -> None:
    """Real isolation permits input reads/output writes but blocks context writes, private reads and network."""
    executable, inputs, outputs, roots = sandbox_paths
    root = inputs.parent
    with socket.socket() as endpoint:
        endpoint.bind(("127.0.0.1", 0))
        endpoint.listen()
        port = endpoint.getsockname()[1]
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            pass
        protected = inputs / "approved.txt"
        protected.write_text("approved", encoding="utf-8")
        alias = root / "input-alias"
        alias.symlink_to(inputs, target_is_directory=True)
        private = root / "private.txt"
        private.write_text("secret", encoding="utf-8")
        program = inputs / "check.py"
        program.write_text(
            "import os, pathlib, socket\n"
            f"protected = pathlib.Path({str(protected)!r})\n"
            "assert protected.read_text() == 'approved'\n"
            f"assert pathlib.Path({str(alias / 'approved.txt')!r}).read_text() == 'approved'\n"
            "try:\n protected.write_text('changed')\n"
            "except OSError as error:\n assert error.errno in (1, 13, 30), repr(error)\n"
            "else:\n raise AssertionError('wrote approved input')\n"
            f"private = pathlib.Path({str(private)!r})\n"
            "try:\n private.read_text()\n"
            "except (PermissionError, FileNotFoundError):\n pass\n"
            "else:\n raise AssertionError('read private data')\n"
            f"try:\n socket.socket().connect(('127.0.0.1', {port}))\n"
            "except OSError as error:\n"
            " assert error.errno in (1, 13, 101, 111, 113), repr(error)\n"
            "else:\n raise AssertionError('network access allowed')\n"
            "assert 'GITHUB_TOKEN' not in os.environ\n"
            "pathlib.Path('result.txt').write_text('isolated')\n",
            encoding="utf-8",
        )
        result = run_sandboxed([str(executable), "-I", str(program)], read_roots=[*roots, alias],
                               write_root=outputs, environment={}, timeout=5)
        assert result.returncode == 0, result.stderr
        assert protected.read_text() == "approved"
        assert (outputs / "result.txt").read_text() == "isolated"


@pytest.mark.unit
@pytest.mark.parametrize("direction", ["read_parent", "write_parent"])
def test_overlapping_roots_rejected(direction: str, sandbox_paths: tuple[Path, Path, Path, list[Path]]) -> None:
    """Overlapping input and output trees reject before selecting or launching a sandbox backend."""
    executable, inputs, outputs, _ = sandbox_paths
    with pytest.raises(ValueError, match="disjoint"):
        sandbox_command([str(executable)], [inputs.parent if direction == "read_parent" else inputs],
                        outputs if direction == "read_parent" else inputs.parent)


@pytest.mark.unit
def test_untrusted_environment_rejected(sandbox_paths: tuple[Path, Path, Path, list[Path]]) -> None:
    """Ambient Python import settings cannot enter the trusted sandbox environment."""
    executable, inputs, outputs, roots = sandbox_paths
    with pytest.raises(ValueError, match="Only trusted Lean"):
        run_sandboxed([str(executable)], read_roots=roots, write_root=outputs,
                      environment={"PYTHONPATH": str(inputs)})


@pytest.mark.integration
@pytest.mark.requires_sandbox
def test_output_limit(sandbox_paths: tuple[Path, Path, Path, list[Path]]) -> None:
    """An output-flooding child fails and retained stdout is bounded to one MiB."""
    executable, _, outputs, roots = sandbox_paths
    noisy = run_sandboxed([str(executable), "-I", "-c", "import sys; sys.stdout.write('x' * 20_000_000)"],
                          read_roots=roots, write_root=outputs, environment={}, timeout=5)
    assert noisy.returncode != 0
    assert len(noisy.stdout) == 1024 * 1024


@pytest.mark.integration
@pytest.mark.requires_sandbox
def test_timeout(sandbox_paths: tuple[Path, Path, Path, list[Path]]) -> None:
    """A nonterminating proof child raises TimeoutExpired within the configured deadline."""
    executable, _, outputs, roots = sandbox_paths
    with pytest.raises(subprocess.TimeoutExpired):
        run_sandboxed([str(executable), "-I", "-c", "while True: pass"], read_roots=roots,
                      write_root=outputs, environment={}, timeout=0.5)


@pytest.mark.integration
@pytest.mark.requires_sandbox
def test_fork_containment(sandbox_paths: tuple[Path, Path, Path, list[Path]]) -> None:
    """macOS denies forks; Linux kills escaped child sessions when the enclosing proof times out."""
    executable, _, outputs, roots = sandbox_paths
    if platform.system() == "Darwin":
        result = run_sandboxed([str(executable), "-I", "-c",
            "import os\ntry:\n os.fork()\nexcept PermissionError:\n pass\n"
            "else:\n raise AssertionError('fork permitted')"],
            read_roots=roots, write_root=outputs, environment={}, timeout=5)
        assert result.returncode == 0, result.stderr
    else:
        with pytest.raises(subprocess.TimeoutExpired):
            run_sandboxed([str(executable), "-I", "-c",
                "import os, pathlib, time\nif os.fork() == 0:\n"
                " os.setsid()\n pathlib.Path('forked').touch()\n"
                " time.sleep(4)\n pathlib.Path('leaked').touch()\nelse:\n time.sleep(60)"],
                read_roots=roots, write_root=outputs, environment={}, timeout=3)
        assert (outputs / "forked").exists()
        time.sleep(2)
        assert not (outputs / "leaked").exists()
