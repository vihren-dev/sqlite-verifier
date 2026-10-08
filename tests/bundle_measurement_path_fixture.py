"""Deterministic three-command runtime fixture for complete paired-path measurement tests."""

from pathlib import Path
import sys

import pytest

from tests.bundle_measurement_fixture import launcher
from tools.bundle_measurement_paths import TrialSpec


@pytest.fixture
def trial_spec(launcher: Path) -> TrialSpec:
    """Exercise the real observer/recorder against an installed fixture with cold preparation and checking."""
    runtime = launcher.parents[1]
    (runtime / "migration_check/prepare.py").write_text('''"""Fixture cold preparation uses its sole public entrypoint."""
from pathlib import Path
from migration_check.contract import compile_contract
def prepare(arguments: list[str]) -> int:
    """Require an empty agent workspace, then retain candidate outputs and one bundle."""
    agent = Path(arguments[arguments.index("--workspace")+1])
    assert not list(agent.iterdir())
    (agent/"modules").mkdir()
    (agent/"modules/Proofs.olean").write_bytes(b"fixture cold compile")
    (agent/"stage-store").mkdir()
    Path(arguments[arguments.index("--output")+1]).write_bytes(b"exact fixture bundle")
    return compile_contract()
''')
    (runtime / "migration_check/bundle.py").write_text('''"""Fixture bundle checking reads exact same-path preparation output."""
from pathlib import Path
from migration_check.contract import compile_contract
from migration_check.process import run_process
def verify_bundle(arguments: list[str]) -> int:
    """Check a retained bundle without a second preparation or a warm candidate workspace."""
    assert Path(arguments[arguments.index("--bundle")+1]).read_bytes()==b"exact fixture bundle"
    run_process(["migration-bundle-checker","library","trusted"])
    return compile_contract()
''')
    cli = runtime / "migration_check/cli.py"
    dispatch = '''if arguments[:1]==["prepare"]:
            from migration_check.prepare import prepare
            count = prepare(arguments[1:])
        elif arguments[:1]==["verify-bundle"]:
            from migration_check.bundle import verify_bundle
            count = verify_bundle(arguments[1:])
        else:
            count = verify(arguments)'''
    cli.write_text(cli.read_text().replace("count = verify(arguments)", dispatch).replace(
        'status = "VIOLATED" if arguments==["negative"] else "VERIFIED"',
        'status = "PREPARED" if arguments[:1]==["prepare"] else "VERIFIED"').replace(
        'status=="VERIFIED"', 'status in ("VERIFIED","PREPARED")'))
    return TrialSpec("fixture", runtime, Path(sys.executable),
                     Path(__file__).resolve().parents[1] / "tools/bundle_measurement_child.py",
                     (runtime / "migration_check",), ("--format", "json"), (), "VERIFIED", 10_000_000_000)
