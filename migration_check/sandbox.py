"""Contain Lean elaboration; source files can execute arbitrary tactic code."""

from collections.abc import Mapping, Sequence
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import signal
import subprocess
from tempfile import TemporaryFile


class SandboxUnavailable(RuntimeError):
    """Refuse verification when the required isolation cannot be established."""


def limit_output_files() -> None:
    """Bound each candidate-created file, including captured output streams."""
    resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 * 1024, 16 * 1024 * 1024))


def sandbox_command(
    arguments: Sequence[str], read_roots: Sequence[Path], write_root: Path
) -> list[str]:
    """Expose only declared input/runtime paths and one temporary output directory."""
    if not arguments:
        raise ValueError("A sandbox requires an executable")
    executable = Path(arguments[0]).resolve(strict=True)
    output = write_root.resolve(strict=True)
    if not executable.is_file() or not output.is_dir():
        raise ValueError("The executable must be a file and output must be a directory")
    bindings = sorted({(path.resolve(strict=True), Path(os.path.abspath(path))) for path in read_roots})
    roots = sorted({resolved for resolved, _ in bindings})
    if output == Path("/") or any(root == Path("/") for root in roots):
        raise ValueError("The filesystem root cannot be exposed to a proof process")
    if executable.is_relative_to(output) or any(
        root.is_relative_to(output) or output.is_relative_to(root) for root in roots
    ):
        raise ValueError("Runtime/input paths and the writable output tree must be disjoint")
    command = [str(executable), *arguments[1:]]
    if platform.system() == "Darwin":
        launcher = Path("/usr/bin/sandbox-exec")
        if not launcher.exists():
            raise SandboxUnavailable("macOS sandbox-exec is required")
        system_roots = [Path("/System"), Path("/usr/lib"), Path("/private/var/db/dyld")]
        reads = " ".join(f"(subpath {json.dumps(str(path))})" for path in roots + system_roots)
        profile = "\n".join([
            "(version 1)",
            "(deny default)",
            f"(allow process-exec (literal {json.dumps(str(executable))}))",
            "(allow sysctl-read)",
            "(allow file-read-metadata)",
            # dyld opens the root directory; this does not grant subtree access.
            "(allow file-read* (literal \"/\"))",
            f"(allow file-read* {reads} (literal \"/dev/null\") (literal \"/dev/urandom\"))",
            f"(allow file-read* file-write* (subpath {json.dumps(str(output))}))",
            "(allow file-write* (literal \"/dev/null\"))",
        ])
        return [str(launcher), "-p", profile, *command]
    if platform.system() == "Linux":
        launcher = shutil.which("bwrap")
        if launcher is None:
            raise SandboxUnavailable("Linux bubblewrap is required")
        wrapped = [launcher, "--unshare-all", "--die-with-parent", "--new-session"]
        for root in roots:
            wrapped.extend(["--ro-bind", str(root), str(root)])
        for resolved, requested in bindings:
            if requested != resolved:
                wrapped.extend(["--ro-bind", str(resolved), str(requested)])
        wrapped.extend([
            "--proc", "/proc", "--dev", "/dev", "--bind", str(output), str(output),
            "--chdir", str(output), "--", *command,
        ])
        return wrapped
    raise SandboxUnavailable(f"No proof sandbox for {platform.system()}")


def run_sandboxed(
    arguments: Sequence[str], *, read_roots: Sequence[Path], write_root: Path,
    environment: Mapping[str, str], timeout: float = 30,
) -> subprocess.CompletedProcess[str]:
    """Run without inherited credentials, shell interpretation, or unbounded time."""
    if timeout <= 0:
        raise ValueError("A positive process timeout is required")
    if set(environment) - {"LEAN_PATH", "LEAN_SYSROOT"}:
        raise ValueError("Only trusted Lean search-path settings may enter the sandbox")
    command = sandbox_command(arguments, read_roots, write_root)
    env = {"HOME": str(write_root), "TMPDIR": str(write_root), "LANG": "C.UTF-8"}
    env.update(environment)
    with TemporaryFile(dir=write_root) as stdout_file, TemporaryFile(dir=write_root) as stderr_file:
        with subprocess.Popen(
            command, cwd=write_root, env=env, stdin=subprocess.DEVNULL,
            stdout=stdout_file, stderr=stderr_file, start_new_session=True,
            preexec_fn=limit_output_files,
        ) as process:
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise
            stdout_file.seek(0)
            stderr_file.seek(0)
            stdout = stdout_file.read(1024 * 1024).decode("utf-8", errors="replace")
            stderr = stderr_file.read(1024 * 1024).decode("utf-8", errors="replace")
            return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
