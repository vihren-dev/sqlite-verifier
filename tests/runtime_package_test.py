"""Independently selectable acceptance checks through the actual installed native runtime."""

from collections.abc import Callable
import os
from pathlib import Path

import pytest

from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.packaging, pytest.mark.requires_nix,
              pytest.mark.requires_native, pytest.mark.requires_lean]


@pytest.fixture(autouse=True)
def require_installed_variant(pytestconfig: pytest.Config) -> None:
    """Never let checkout binaries masquerade as installed-package acceptance."""
    if pytestconfig.getoption("runtime_variant") != "installed":
        pytest.fail("Installed acceptance requires --runtime-variant installed and an installed root or archive")


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_installed_parser(version: str, runtime_root: Path, tmp_path: Path,
                          command_runner: Callable[..., CommandResult]) -> None:
    """Both installed parsers retain their exact SQLite profiles under poisoned ambient imports."""
    parser = "sqlite-parser" if version == "3.51.0" else "sqlite-parser-3.46.0"
    result = command_runner([str(runtime_root / "build" / parser),
                             str(runtime_root / "examples/approved/schema.sql")], cwd=tmp_path, timeout=10)
    assert result.returncode == 0, result.diagnostic()
    assert result.json_object()["profile"] == version, result.diagnostic()


@pytest.fixture
def installed_verify(runtime_root: Path, tmp_path: Path,
                     command_runner: Callable[..., CommandResult]) -> Callable[..., CommandResult]:
    """Bind installed examples and launcher together without importing checkout implementation."""
    def invoke(candidate: str, *, migration: Path | None = None, timeout: int = 180) -> CommandResult:
        """Use the original public seven inputs and retain the installed test deadlines."""
        approved = runtime_root / "examples/approved"
        proposed = runtime_root / "examples" / candidate
        return command_runner([str(runtime_root / "bin/migration-check"), "verify", "--profile", "3.51.0",
            "--format", "json", "--schema", str(approved / "schema.sql"),
            "--requirements", str(approved / "Requirements.lean"),
            "--interpretation", str(approved / "Interpretation.lean"),
            "--migration", str(migration or proposed / "migration.sql"),
            "--next-interpretation", str(proposed / "NextInterpretation.lean"),
            "--proofs", str(proposed / "Proofs.lean"),
            "--approved-baseline", str(approved / "baseline.json")], cwd=tmp_path, timeout=timeout)
    return invoke


def test_verified_example(installed_verify: Callable[..., CommandResult]) -> None:
    """The installed entrypoint independently verifies the shipped positive migration."""
    result = installed_verify("add_column_then_table")
    assert result.returncode == 0 and result.json_object()["status"] == "VERIFIED", result.diagnostic()


def test_refuted_example(installed_verify: Callable[..., CommandResult]) -> None:
    """The installed entrypoint returns VIOLATED and nonzero for a kernel-checked refutation."""
    result = installed_verify("missing_required_column")
    assert result.returncode != 0 and result.json_object()["status"] == "VIOLATED", result.diagnostic()


@pytest.mark.parametrize("candidate,approved", [
    ("table_then_column", "approved"),
    ("allowed_failure", "allowed_failure/approved"),
])
def test_other_protected_examples(runtime_root: Path, tmp_path: Path,
        command_runner: Callable[..., CommandResult], candidate: str, approved: str) -> None:
    """Every other invoice candidate verifies with its actual installed protected baseline."""
    examples = runtime_root / "examples"
    proposed, protected = examples / candidate, examples / approved
    result = command_runner([str(runtime_root / "bin/migration-check"), "verify", "--profile", "3.51.0",
        "--format", "json", "--schema", str(protected / "schema.sql"),
        "--requirements", str(protected / "Requirements.lean"),
        "--interpretation", str(protected / "Interpretation.lean"),
        "--migration", str(proposed / "migration.sql"),
        "--next-interpretation", str(proposed / "NextInterpretation.lean"),
        "--proofs", str(proposed / "Proofs.lean"),
        "--approved-baseline", str(protected / "baseline.json")], cwd=tmp_path, timeout=180)
    assert result.returncode == 0 and result.json_object()["status"] == "VERIFIED", result.diagnostic()


def test_installed_protected_schema_precedes_invalid_proof(runtime_root: Path, tmp_path: Path,
        example_factory: Callable[[str], Path], command_runner: Callable[..., CommandResult]) -> None:
    """The installed driver rejects changed schema bytes before deliberately invalid Lean proof code."""
    examples = example_factory(".")
    protected, proposed = examples / "approved", examples / "add_column_then_table"
    schema = protected / "schema.sql"
    schema.write_bytes(schema.read_bytes() + b"\n-- unapproved schema source change\n")
    (proposed / "Proofs.lean").write_text("import Generated\ndef invalidProof : Nat := false\n")
    result = command_runner([str(runtime_root / "bin/migration-check"), "verify", "--profile", "3.51.0",
        "--format", "json", "--schema", str(schema), "--requirements", str(protected / "Requirements.lean"),
        "--interpretation", str(protected / "Interpretation.lean"), "--migration", str(proposed / "migration.sql"),
        "--next-interpretation", str(proposed / "NextInterpretation.lean"), "--proofs", str(proposed / "Proofs.lean"),
        "--approved-baseline", str(protected / "baseline.json")], cwd=tmp_path, timeout=30)
    report = result.json_object()
    assert result.returncode == 1 and report["status"] == "INPUT_ERROR", result.diagnostic()
    assert "schema.sql" in report["message"], result.diagnostic()


def test_unsupported_migration(installed_verify: Callable[..., CommandResult], tmp_path: Path) -> None:
    """The installed entrypoint rejects unsupported DROP TABLE before proof acceptance."""
    migration = tmp_path / "unsupported.sql"
    migration.write_text("DROP TABLE invoices;\n")
    result = installed_verify("missing_required_column", migration=migration, timeout=30)
    assert result.returncode != 0 and result.json_object()["status"] == "UNSUPPORTED", result.diagnostic()


def test_installed_gc_roots(runtime_root: Path, tmp_path: Path,
                           command_runner: Callable[..., CommandResult]) -> None:
    """Installation registers one Nix GC root that retains the linked runtime store path."""
    store_path = (runtime_root / "bin").resolve().parent
    roots = list((runtime_root / ".nix-roots").iterdir())
    assert [root.resolve() for root in roots] == [store_path]
    registered = command_runner(["nix-store", "--query", "--roots", str(store_path)], cwd=tmp_path,
                                timeout=30, environment=dict(os.environ))
    assert registered.returncode == 0 and str(roots[0]) in registered.stdout, registered.diagnostic()


@pytest.mark.parametrize("candidate,checked_migration,status", [
    ("add_column_then_table", None, "VERIFIED"),
    ("missing_required_column", None, "VIOLATED"),
    ("add_column_then_table", "table_then_column", "UNVERIFIED"),
], ids=["verified", "refuted", "wrong_sql_rejected"])
def test_installed_data_path(runtime_root: Path, tmp_path: Path, command_runner: Callable[..., CommandResult],
                             candidate: str, checked_migration: str | None, status: str) -> None:
    """The installed `prepare` and `verify-bundle` reproduce the source statuses under poisoned imports."""
    examples = runtime_root / "examples"
    launcher = str(runtime_root / "bin/migration-check")

    def common(migration: str) -> list[str]:
        """Contract and SQL arguments for the shipped approved example."""
        return ["--profile", "3.51.0", "--format", "json", "--schema", str(examples / "approved/schema.sql"),
                "--requirements", str(examples / "approved/Requirements.lean"),
                "--interpretation", str(examples / "approved/Interpretation.lean"),
                "--migration", str(examples / migration / "migration.sql")]

    bundle = tmp_path / "proof.bundle"
    prepared = command_runner([launcher, "prepare", *common(candidate),
                               "--next-interpretation", str(examples / candidate / "NextInterpretation.lean"),
                               "--proofs", str(examples / candidate / "Proofs.lean"),
                               "--workspace", str(tmp_path / "agent"), "--output", str(bundle)],
                              cwd=tmp_path, timeout=180)
    assert prepared.returncode == 0 and prepared.json_object()["status"] == "PREPARED", prepared.diagnostic()
    checked = command_runner([launcher, "verify-bundle", *common(checked_migration or candidate),
                              "--bundle", str(bundle)], cwd=tmp_path, timeout=120)
    assert checked.json_object()["status"] == status, checked.diagnostic()
    assert checked.returncode == (0 if status == "VERIFIED" else 1), checked.diagnostic()


def test_installed_model_and_codec_consumer(runtime_root: Path, tmp_path: Path,
        command_runner: Callable[..., CommandResult]) -> None:
    """An unrelated installed consumer compiles core, codec and application imports from both roots."""
    source = tmp_path / 'NeutralConsumer.lean'
    source.write_text('import Belay.Sqlite\nimport Belay.Sqlite.Codec\nimport SqliteVerifier\n'
        '#check Belay.Sqlite.Conforms.set\n#check Belay.Sqlite.TableExtends.project\n'
        '#check SqliteVerifier.VerificationConditions\n'
        'def inputs : Belay.Sqlite.GeneratedInputs := ⟨1, .sqlite351, [], [], []⟩\n'
        '#eval match Belay.Sqlite.decodeGeneratedInputs (Lean.toJson inputs) with\n'
        '  | .ok value => value.version == 1\n  | .error _ => false\n')
    roots = (runtime_root / '.lake/build/lib/lean',
             runtime_root / 'packages/belay-sqlite/.lake/build/lib/lean')
    result = command_runner([str(runtime_root / 'lean/bin/lean'), str(source)],cwd=tmp_path,
        timeout=30,environment={'LEAN_SYSROOT':str(runtime_root / 'lean'),
                               'LEAN_PATH':os.pathsep.join(map(str,roots))})
    assert result.returncode == 0 and 'true' in result.stdout.splitlines(),result.diagnostic()


def test_installed_namespace_frontend(runtime_root: Path, tmp_path: Path,
        command_runner: Callable[..., CommandResult]) -> None:
    """The pinned installed Python imports only the shipped namespace frontend under poisoned paths."""
    python = (runtime_root / 'python-path').read_text().strip()
    code = '''import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root))
import belay.sqlite
from belay.sqlite.profiles import profile
from belay.sqlite.sql_model import Column
assert not (root / 'belay/__init__.py').exists()
assert {path.name for path in (root / 'belay').iterdir()} == {'sqlite'}
assert profile('3.46.0').wire_tag == 'sqlite346'
assert Column('value', 'text').name == 'value'
assert not any(name.startswith('migration_check') for name in sys.modules)
print('INSTALLED_FRONTEND')
'''
    result = command_runner([python,'-I','-c',code,str(runtime_root)],cwd=tmp_path,timeout=15)
    assert result.returncode == 0 and result.stdout.strip() == 'INSTALLED_FRONTEND',result.diagnostic()
