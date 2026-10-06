"""A deterministic installed-launcher fixture for fresh-process observation tests."""

from pathlib import Path

import pytest


@pytest.fixture
def launcher(tmp_path: Path) -> Path:
    """An isolated public launcher reads one runtime package and returns its unchanged CLI protocol."""
    runtime = tmp_path / "runtime"
    (runtime / "bin").mkdir(parents=True)
    (runtime / "migration_check").mkdir()
    (runtime / "migration_check/__init__.py").write_text('"""Deterministic runtime fixture."""\n')
    (runtime / "migration_check/contract.py").write_text('''"""A bounded observable fixture stage."""
from time import sleep
count = 0
def compile_contract(fail: bool = False) -> int:
    """Count a real stage call in this child only."""
    global count
    count += 1
    sleep(0.005)
    if fail:
        raise ValueError("fixture stage failed")
    return count
''')
    (runtime / "migration_check/process.py").write_text('''"""Bounded external-role fixture calls."""
from time import sleep
import subprocess
def run_process(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    """Exercise the real profiling boundary with known command roles."""
    sleep(0.001)
    return subprocess.CompletedProcess(arguments,0,"","")
''')
    (runtime / "migration_check/cli.py").write_text('''"""The fixture's sole command entrypoint."""
import json,os,sys
import migration_check.contract as contract
from migration_check.process import run_process
def verify(arguments: list[str]) -> int:
    """Use the existing fixture stage."""
    run_process(["lean", "--deps-json", "Proofs.lean"])
    run_process(["lean", "-o", "Proofs.olean", "Proofs.lean"])
    run_process(["migration-proof-checker", "library", "trusted"])
    return contract.compile_contract(arguments==["error"])
def main(arguments: list[str]) -> int:
    """Preserve the fixture public report and exit code."""
    try:
        count = verify(arguments)
        status = "VIOLATED" if arguments==["negative"] else "VERIFIED"
    except ValueError:
        count, status = contract.count, "UNVERIFIED"
    print(json.dumps({"status":status,
                      "count":count,"pid":os.getpid(),"isolated":sys.flags.isolated}))
    return 0 if status=="VERIFIED" else 1
''')
    entry = runtime / "bin/migration-check"
    entry.write_text('''"""Route the fixture through its sole CLI entrypoint."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from migration_check.cli import main
raise SystemExit(main(sys.argv[1:]))
''')
    return entry

