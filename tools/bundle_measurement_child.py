"""Observe stages while executing the installed public launcher in one fresh isolated process."""

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys
from time import monotonic_ns
from types import FrameType

STAGES = {
    ("cli", "verify"), ("bundle", "verify_bundle"), ("prepare", "prepare"),
    ("inputs", "generated_inputs"), ("sql_tree", "parse"),
    ("contract", "compile_contract"), ("compile", "compile_project"),
    ("compile", "compile_modules"), ("source_closure", "discover_sources"),
    ("prepare", "compile_candidates"), ("prepare", "export_bundle"),
    ("process", "run_process"), ("stage_store", "restore"), ("stage_store", "save"),
}


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


class StageObserver:
    """Profile actual current callers without replacing functions, inputs or acceptance."""

    def __init__(self, runtime: Path) -> None:
        """Bind observable frames to this runtime's source modules before the launcher executes."""
        self.modules = runtime.resolve() / "migration_check"
        self.prefix = str(self.modules) + os.sep
        self.active: dict[FrameType, tuple[int, int | None, str, int, str]] = {}
        self.spans: list[Span] = []
        self.hashes: dict[str, str] = {}
        self.next_identifier = 0

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
                executable = Path(command[0]).name if command else "empty"
                if "--deps-json" in command:
                    return "process:dependencies"
                if command and str(command[-1]).endswith(".lean"):
                    return "process:compile:" + Path(command[-1]).stem
                return "process:" + executable
        return module + ":" + function

    def observe(self, frame: FrameType, event: str, argument: object) -> None:
        """Retain monotonic timestamps from this invocation, including stages ending in errors."""
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
            self.spans.append(Span(identifier, parent_identifier, stage, started, ended, os.getpid(),
                                   source, self.hashes[source]))


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
    observer = StageObserver(launcher.parents[1])
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
            "spans": [asdict(span) for span in sorted(observer.spans, key=lambda value: value.identifier)],
            "active_stages": len(observer.active), "isolated_python": True}) + "\n")


if __name__ == "__main__":
    main()
