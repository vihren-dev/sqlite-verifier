"""Measure candidate `prepare`/`verify-bundle` speedups as in-process patches.

Usage: python3 experiments/prepare-latency/prototypes.py TRIALS OPTION[,OPTION...] > out.jsonl

Options (comma-separated; "none" is the unpatched baseline):

- wait: wait for each child with a blocking wait and a kill timer, instead of
  `Popen.wait(timeout)`, which polls with sleeps of up to 50 ms.
- validate: scan the trusted library trees once per process instead of on every
  `Runtime.locate` and contract compile.
- header: read `import` lines in Python instead of running `lean --deps-json`.
  Only for measurement: the result is compared with Lean's on every example first.
- parallel: in `prepare`, compile candidate modules whose imports are ready at the
  same time, one topological level after another.

These patches are measurement prototypes, not proposed implementations. They do
not change the verifier sources.
"""

from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
import functools
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
from tempfile import TemporaryDirectory, TemporaryFile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import profile_data_path as harness  # noqa: E402  (installs the timing wrappers)

from migration_check import contract, process, runtime, source_closure  # noqa: E402
from migration_check import prepare as prepare_module  # noqa: E402

CAPTURED_OUTPUT_BYTES = 1 << 20
"""Bytes read from each captured child stream, the same bound as `process.run_process`."""

ORIGINAL_IMPORTS = source_closure.imports
"""Lean-backed import reader, kept to check the header prototype against it."""


def blocking_run_process(arguments: Sequence[str], *, write_root: Path, environment: dict[str, str],
                         timeout: float = 30) -> subprocess.CompletedProcess[str]:
    """`process.run_process` with a blocking wait; a timer kills the process group on timeout."""
    command = list(arguments)
    env = {"HOME": str(write_root), "TMPDIR": str(write_root), "LANG": "C.UTF-8", **environment}
    with TemporaryFile(dir=write_root) as stdout_file, TemporaryFile(dir=write_root) as stderr_file:
        with subprocess.Popen(command, cwd=write_root, env=env, stdin=subprocess.DEVNULL, stdout=stdout_file,
                              stderr=stderr_file, start_new_session=True,
                              preexec_fn=process.limit_output_files) as child:
            expired = threading.Event()

            def kill() -> None:
                """Kill the whole process group once the deadline passes."""
                expired.set()
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            timer = threading.Timer(timeout, kill)
            timer.start()
            try:
                child.wait()
            finally:
                timer.cancel()
            if expired.is_set():
                raise subprocess.TimeoutExpired(command, timeout)
            stdout_file.seek(0)
            stderr_file.seek(0)
            return subprocess.CompletedProcess(command, child.returncode,
                                               stdout_file.read(CAPTURED_OUTPUT_BYTES).decode("utf-8", "replace"),
                                               stderr_file.read(CAPTURED_OUTPUT_BYTES).decode("utf-8", "replace"))


IMPORT_LINE = re.compile(r"^import\s+(\S+)\s*$")


def header_imports(source: Path, *_: object) -> tuple[str, ...]:
    """Read leading `import` lines, skipping blank and `--` comment lines.

    Like Lean, report the implicit `Init` import first unless the header starts with `prelude`.
    """
    names: list[str] = ["Init"]
    for line in source.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        if stripped == "prelude" and names == ["Init"]:
            names = []
            continue
        match = IMPORT_LINE.match(stripped)
        if match is None:
            break
        names.append(match.group(1))
    return tuple(dict.fromkeys(names))


def check_header_prototype() -> None:
    """Refuse to measure the header prototype unless it agrees with Lean on every example source."""
    located = runtime.Runtime.locate("3.51.0")
    with TemporaryDirectory() as temporary:
        for source in sorted((harness.ROOT / "examples").rglob("*.lean")):
            expected = ORIGINAL_IMPORTS(source, located.sysroot, located.libraries, Path(temporary))
            if header_imports(source) != expected:
                raise SystemExit(f"Header prototype result differs from Lean on {source}: Lean reports "
                                 f"{expected}. Correct header_imports in prototypes.py, then measure again.")


def parallel_compile_candidates(*, order: tuple[str, ...], sources: Path, candidate: Path, trusted: Path,
                                cache: Path, keys: dict[str, str], runtime: runtime.Runtime,
                                workspace: Path) -> tuple[int, int]:
    """`prepare.compile_candidates`, but modules whose local imports are done compile concurrently."""
    local = set(order)
    pending = {name: {dependency for dependency in header_imports(
        (sources / source_closure.module_path(name)).with_suffix(".lean")) if dependency in local}
        for name in order}
    compiled, reused, done = 0, 0, set[str]()
    lock = threading.Lock()

    def build(name: str) -> bool:
        """Compile one module into its cache entry; True when it was compiled, not reused."""
        relative = source_closure.module_path(name)
        entry = cache / keys[name]
        if (entry / relative.parent / f"{relative.name}.olean").is_file():
            return False
        shutil.rmtree(entry, ignore_errors=True)
        with TemporaryDirectory(prefix="module-", dir=workspace) as temporary:
            output = Path(temporary)
            prepare_module.compile_modules(order=(name,), sources=sources, destination=output,
                                           previous=(trusted, candidate), sysroot=runtime.sysroot,
                                           libraries=runtime.libraries, workspace=workspace)
            with lock:
                cache.mkdir(parents=True, exist_ok=True)
            shutil.copytree(output, entry, dirs_exist_ok=True)
        return True

    with ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
        while len(done) < len(order):
            ready = [name for name in order if name not in done and pending[name] <= done]
            for name, fresh in zip(ready, pool.map(build, ready)):
                compiled, reused = compiled + fresh, reused + (not fresh)
                shutil.copytree(cache / keys[name], candidate, dirs_exist_ok=True)
                done.add(name)
    return compiled, reused


def install(options: set[str]) -> None:
    """Apply the selected prototypes to the imported verifier modules."""
    if "header" in options:
        check_header_prototype()
        source_closure.imports = header_imports
    if "wait" in options:
        timed = harness.recorded(blocking_run_process)
        source_closure.run_process = timed
        harness.bundle.run_process = timed
    if "validate" in options:
        cached = functools.lru_cache(maxsize=None)(runtime.validate_libraries)
        for module in (runtime, contract):
            module.validate_libraries = cached  # type: ignore[attr-defined]
        locate: Callable[[str], runtime.Runtime] = functools.lru_cache(maxsize=None)(runtime.Runtime.locate)
        runtime.Runtime.locate = staticmethod(locate)  # type: ignore[method-assign,assignment]
    if "parallel" in options:
        prepare_module.compile_candidates = parallel_compile_candidates


if __name__ == "__main__":
    trials = int(sys.argv[1])
    selected = set(sys.argv[2].split(",")) - {"none"}
    install(selected)
    for case in harness.CASES:
        for trial in range(trials):
            copy, base = harness.fresh_copy(case, trial)
            for name, command in harness.scenarios(copy, base):
                print(json.dumps({"options": sys.argv[2], "case": case.name, "trial": trial + 1,
                                  "scenario": name, **harness.summary(command)}), flush=True)
