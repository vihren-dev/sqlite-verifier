"""The parameters of `sql r"..."` and `db!` over the surface (`packages/belay`, ADR 0017, S3):
the examples of the user guide's section "Parameters" that need no program, and the errors at
the parameter in the SQL text. Each fixture fails to elaborate when an example does not hold.
"""

from pathlib import Path

import pytest

from tests.runtime_support import run_command
from tests.surface_support import FIXTURES, surface_command

pytestmark = [pytest.mark.integration, pytest.mark.parser, pytest.mark.requires_lean("compiler")]


def test_guide_parameters_examples_hold(runtime_root: Path, tmp_path: Path) -> None:
    """The section "Parameters" (`Belay/Sqlite/SqlParameters.lean`, `Belay/Sqlite/SqlTerm.lean`,
    the coercions of `Belay/Sqlite/Values.lean`, `check_query` of `Belay/Sqlite/Queries.lean`):
    the guide's `nameOf` and `setAmount` with its `#check` and named call; `$x` of `Value`,
    `String` and `Int64`; the numbers and the order of the arguments; one argument for a name in
    two statements; `Script.withValues` over the term; and `Holds` and `Empty` of a query with
    parameters, which the kernel decides."""
    result = run_command(surface_command(runtime_root, FIXTURES / "GuideParameters.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 0, result.diagnostic()


def test_parameter_errors_are_at_the_parameter(runtime_root: Path, tmp_path: Path) -> None:
    """A wrong parameter of `sql r"..."` (`planParameters` of `Belay/Sqlite/SqlParameters.lean`,
    `variableValue` of `Belay/Sqlite/SqlTerm.lean`) and each parameter of `db!`
    (`Belay/Sqlite/DbBang.lean`) is an error at the parameter in the SQL text, with a message
    that says what to do: `$x` without a variable, `$x` of a type without a coercion to `Value`,
    a `$` name that is not a Lean identifier, two parameters that give one Lean name, and two
    parameters of one statement with one number and two Lean names."""
    result = run_command(surface_command(runtime_root, FIXTURES / "ParameterErrors.lean", tmp_path), cwd=tmp_path,
                         timeout=60)
    assert result.returncode == 1, result.diagnostic()
    expected = [
        ("14:45", "the parameter $nosuch is the Lean variable nosuch, and Lean cannot elaborate it: Unknown identifier"),
        ("16:54", "the parameter $n is the Lean variable n of type NoValue, which has no coercion to Value"),
        ("18:43", "the parameter $a::b must name a Lean variable, and its name is not a Lean identifier"),
        ("20:47", "the parameter $a(x) must name a Lean variable"),
        ("22:36", "the parameters :id and @id both give the Lean name id; rename one of them"),
        ("24:60", "the parameters :id and $id both give the Lean name id; rename one of them"),
        ("26:54", "SQLite gives the parameters $x and ?1 of this statement one number, 1"),
        ("28:38", "SQLite gives the parameters :a and ?1 of this statement one number, 1"),
        ("30:76", "the parameter :a has no value, because db! has no arguments"),
        ("30:82", "the parameter ? has no value, because db! has no arguments"),
    ]
    for position, message in expected:
        assert f"ParameterErrors.lean:{position}: error: {message}" in result.stdout, result.diagnostic()
    assert result.stdout.count(": error") == len(expected), result.diagnostic()
