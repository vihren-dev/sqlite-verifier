"""The programs of the surface (`packages/belay`, ADR 0017, S3): `Sql α` in `do` notation with
`send`, `query` and `single`, their runs with `db.run` and `Sql.run`, and the clock of `Env` with
`clockAt`. Each fixture fails to elaborate when an example does not hold.
"""

from pathlib import Path

import pytest

from tests.runtime_support import run_command
from tests.surface_support import FIXTURES, surface_command

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_lean("compiler")]


def test_guide_program_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The guide's sections "Programs", "Running a program" and "The execution environment"
    (`Belay/Sqlite/Program.lean`, `ProgramQueries.lean`, `ProgramRun.lean`, `ProgramLaws.lean`,
    `Env.lean` and `ValueDisplay.lean` of `Belay/Sqlite`): `addCustomer` and its kernel example,
    `closeAndCount`, `demo` with the value that `#eval` shows, `main` (elaborated, not run), a run
    under `clockAt`, a clock read under `Env.default`, and `Script.run_env`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuidePrograms.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_program_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The kernel examples of programs (`Sql.runFrom` and `Run.checked` of
    `Belay/Sqlite/ProgramRun.lean`, `query` and `single` of `Belay/Sqlite/ProgramQueries.lean`, the
    laws of `Belay/Sqlite/ProgramLaws.lean` and `Belay/Sqlite/RunLaws.lean`, the clock of
    `Belay/Sqlite/Env.lean`): `query` and `single` on each output kind; a clock read that ends a
    program; a value that depends on an earlier output; the run of `send s` as the model's run
    of `s`; the clock's text under `clockAt` and `Output.unmodeled` without a clock; and the laws
    applied to programs and scripts."""
    result = run_command(surface_command(runtime_root, FIXTURES / "ProgramExamples.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_program_errors_are_at_their_position(runtime_root: Path, tmp_path: Path) -> None:
    """`query` and `single` of a script that is not one statement (`check_one_statement` of
    `Belay/Sqlite/ProgramQueries.lean`) are an error at the function, also with a `$x` value, and
    `clockAt` of a text that is not a time (`timeOfText?` of `Belay/Sqlite/Env.lean`) is an error
    at the text. The fixture checks each message and position with
    `#guard_msgs (positions := true)`."""
    result = run_command(surface_command(runtime_root, FIXTURES / "ProgramErrors.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()
