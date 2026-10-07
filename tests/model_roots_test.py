"""Both installed model roots are explicit, protected and available to unrelated callers."""

from pathlib import Path
from collections.abc import Callable
import shutil

import pytest

from migration_check.runtime import validate_libraries
from migration_check.stage_store import runtime_identity
from tests.runtime_support import run_command, CommandResult
from tests.proof_exporter_test import prepare_check, CASES

pytestmark = [pytest.mark.integration, pytest.mark.kernel, pytest.mark.requires_lean]


def test_model_change_invalidates_runtime_identity(tmp_path: Path) -> None:
    """A different model artifact changes stage identity even when the compiler and application stay fixed."""
    application, first, second = (tmp_path / name for name in ('application', 'first', 'second'))
    assert runtime_identity(tmp_path, (application, first)) != runtime_identity(tmp_path, (application, second))


def test_missing_model_root_is_refused(lean_sysroot: Path, lean_libraries: tuple[Path, Path],
                                      tmp_path: Path) -> None:
    """A valid application root cannot satisfy the required separate model installation."""
    with pytest.raises(ValueError, match='missing or relative'):
        validate_libraries(lean_sysroot, (lean_libraries[0], tmp_path / 'missing'))


def test_colliding_model_is_refused_by_both_gates(runtime_root: Path, lean_sysroot: Path,
        lean_libraries: tuple[Path, Path], tmp_path: Path) -> None:
    """A duplicate installed module fails before either gate imports caller declarations."""
    application = tmp_path / 'application'
    duplicate = application / 'Belay/Sqlite.olean'
    duplicate.parent.mkdir(parents=True)
    shutil.copyfile(lean_libraries[1] / 'Belay/Sqlite.olean', duplicate)
    with pytest.raises(ValueError, match='conflicts'):
        validate_libraries(lean_sysroot, (application, lean_libraries[1]))
    trusted, candidate = tmp_path / 'trusted', tmp_path / 'candidate'
    trusted.mkdir(); candidate.mkdir()
    bundle = tmp_path / 'bundle'
    bundle.write_text('{"bundle":1,"trusted_imports":[]}\n')
    generated = tmp_path / 'generated.json'
    generated.write_text('{}')
    for executable, arguments in [('migration-proof-checker', [str(candidate)]),
                                 ('migration-bundle-checker', [str(bundle), str(generated)])]:
        result = run_command([str(runtime_root / '.lake/build/bin' / executable),
            str(application), str(lean_libraries[1]), str(trusted), *arguments],
            cwd=tmp_path, timeout=30, environment={'LEAN_SYSROOT':str(lean_sysroot)})
        assert result.returncode == 1 and 'conflicts' in result.stderr, result.diagnostic()

def test_candidate_model_namespace_is_exported(runtime_root: Path, example_factory: Callable[[str], Path],
        tmp_path: Path, command_runner: Callable[..., CommandResult]) -> None:
    """A model-like namespace grants no omission or trust to caller-owned declarations."""
    examples = tmp_path / 'model-prefix'
    examples.mkdir()
    for original, name in [('approved', 'approved'), ('add_column_then_table', 'add_column_then_table')]:
        import shutil
        shutil.copytree(example_factory(original), examples / name)
    candidate = examples / 'add_column_then_table'
    helper = candidate / 'Belay/Sqlite/Candidate.lean'
    helper.parent.mkdir(parents=True)
    helper.write_text("import Generated\nimport SqliteVerifier.Demonstration\n"
        "theorem Belay.Sqlite.callerProof : Generated.expected := SqliteVerifier.Demonstration.migrationCorrect\n")
    (candidate / 'Proofs.lean').write_text("import Belay.Sqlite.Candidate\n"
        "theorem Proofs.migrationCorrect : Generated.expected := Belay.Sqlite.callerProof\n")
    _bundle, report = prepare_check(runtime_root, examples, tmp_path, *CASES['small'], command_runner)
    assert report['status'] == 'VERIFIED', report

