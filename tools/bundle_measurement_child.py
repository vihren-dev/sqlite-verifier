"""Observe stages while executing the installed public launcher in one fresh isolated process."""

import argparse
from collections.abc import Sequence
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
from time import monotonic_ns
from types import FrameType

# Driver functions whose calls become spans; the current-caller test detects renamed or removed stages.
STAGES = {
    ("cli", "verify"), ("bundle", "verify_bundle"), ("prepare", "prepare"),
    ("inputs", "generated_inputs"), ("sql_tree", "parse"),
    ("contract", "compile_contract"), ("compile", "compile_project"),
    ("compile", "compile_modules"), ("source_closure", "discover_sources"),
    ("prepare", "compile_candidates"), ("prepare", "export_bundle"),
    ("process", "run_process"), ("stage_store", "restore"), ("stage_store", "save"),
}


def process_journal_path(trace: Path) -> Path:
    """Use one shared trace-to-journal rule so observer creation and timeout cleanup find the same evidence."""
    return trace.with_suffix(".processes.jsonl")


def process_role(arguments: Sequence[str]) -> str:
    """Identify current dependency scans, Lean module compiles and checker/executable calls."""
    if "--deps-json" in arguments:
        return "process:dependencies"
    if arguments and arguments[-1].endswith(".lean"):
        return "process:compile:" + Path(arguments[-1]).stem
    return "process:" + (Path(arguments[0]).name if arguments else "empty")


@dataclass(frozen=True)
class Span:
    """Inclusive spans remain separate so nested stages cannot be summed as whole wall time."""

    identifier: int
    parent_identifier: int | None
    stage: str
    started_ns: int
    ended_ns: int
    pid: int
    source: str
    source_sha256: str
    returncode: int | None
    """Actual external process result when this stage returns CompletedProcess; other stages leave it unobserved."""


@dataclass(frozen=True)
class Spawn:
    """A same-invocation child identity permits bounded cleanup of runtime-created process groups."""

    pid: int
    process_group: int | None
    started_ns: int
    command: tuple[str, ...]


class StageObserver:
    """Profile actual current callers without replacing functions, inputs or acceptance."""

    def __init__(self, runtime: Path, process_journal: Path) -> None:
        """Bind observable frames to this runtime's source modules before the launcher executes."""
        self.modules = runtime.resolve() / "migration_check"
        self.prefix = str(self.modules) + os.sep
        self.active: dict[FrameType, tuple[int, int | None, str, int, str]] = {}
        self.spans: list[Span] = []
        self.hashes: dict[str, str] = {}
        self.next_identifier = 0
        self.process_journal = process_journal
        self.process_journal.write_text("")
        self.processes: list[Spawn] = []

    def label(self, frame: FrameType) -> str | None:
        """Name only stages in the installed runtime; record bounded external process roles."""
        filename = frame.f_code.co_filename
        if not filename.startswith(self.prefix):
            return None
        module, function = Path(filename).stem, frame.f_code.co_name
        if (module, function) not in STAGES:
            return None
        if (module, function) == ("process", "run_process"):
            command = frame.f_locals.get("arguments")
            if isinstance(command, (list, tuple)) and all(isinstance(part, str) for part in command):
                return process_role(command)
        return module + ":" + function

    def observe(self, frame: FrameType, event: str, argument: object) -> None:
        """Retain monotonic timestamps from this invocation, including stages ending in errors."""
        if (event == "return" and frame.f_code.co_name == "__init__"
                and frame.f_globals.get("__name__") == "subprocess"):
            process = frame.f_locals.get("self")
            if isinstance(process, subprocess.Popen) and type(process.pid) is int:
                try:
                    group = os.getpgid(process.pid)
                except ProcessLookupError:
                    group = None
                command = process.args
                parts = (command,) if isinstance(command, str) else tuple(map(str, command))
                spawn = Spawn(process.pid, group, monotonic_ns(), parts)
                self.processes.append(spawn)
                with self.process_journal.open("a") as stream:
                    stream.write(json.dumps(asdict(spawn)) + "\n")
        if event == "call":
            stage = self.label(frame)
            if stage is None:
                return
            parent = frame.f_back
            while parent is not None and parent not in self.active:
                parent = parent.f_back
            parent_identifier = self.active[parent][0] if parent is not None else None
            self.active[frame] = (self.next_identifier, parent_identifier, stage, monotonic_ns(),
                                  frame.f_code.co_filename)
            self.next_identifier += 1
        elif event == "return" and frame in self.active:
            identifier, parent_identifier, stage, started, source = self.active.pop(frame)
            ended = monotonic_ns()
            if source not in self.hashes:
                self.hashes[source] = hashlib.sha256(Path(source).read_bytes()).hexdigest()
            returncode = argument.returncode if isinstance(argument, subprocess.CompletedProcess) else None
            self.spans.append(Span(identifier, parent_identifier, stage, started, ended, os.getpid(),
                                   source, self.hashes[source], returncode))


def main() -> None:
    """Run the same installed launcher and argv, with raw stage evidence in a separate file."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launcher", type=Path, required=True)
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    if not sys.flags.isolated:
        parser.error("Stage observation requires isolated Python; use the installed interpreter with -I")
    launcher = options.launcher.resolve(strict=True)
    arguments = options.arguments[1:] if options.arguments[:1] == ["--"] else options.arguments
    observer = StageObserver(launcher.parents[1], process_journal_path(options.trace))
    before = hashlib.sha256(launcher.read_bytes()).hexdigest()
    sys.argv = [str(launcher), *arguments]
    started = monotonic_ns()
    sys.setprofile(observer.observe)
    try:
        runpy.run_path(str(launcher), run_name="__main__")
    finally:
        sys.setprofile(None)
        ended = monotonic_ns()
        after = hashlib.sha256(launcher.read_bytes()).hexdigest()
        options.trace.write_text(json.dumps({"pid": os.getpid(), "started_ns": started, "ended_ns": ended,
            "launcher": str(launcher), "launcher_sha256_before": before, "launcher_sha256_after": after,
            "observer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "processes": [asdict(spawn) for spawn in observer.processes],
            "spans": [asdict(span) for span in sorted(observer.spans, key=lambda value: value.identifier)],
            "active_stages": len(observer.active), "isolated_python": True}) + "\n")


if __name__ == "__main__":
    main()
