"""Independently selectable acceptance checks through the actual installed native runtime."""

from collections.abc import Callable
import os
from pathlib import Path
import sys

import pytest

from migration_check.project_config import case_names, load
from tests.runtime_support import CommandResult

pytestmark = [pytest.mark.e2e, pytest.mark.packaging, pytest.mark.requires_nix,
              pytest.mark.requires_native, pytest.mark.requires_lean]


@pytest.fixture(autouse=True)
def require_installed_variant(pytestconfig: pytest.Config) -> None:
    """Never let checkout binaries masquerade as installed-package acceptance."""
    if pytestconfig.getoption("runtime_variant") != "installed":
        pytest.fail("Installed acceptance requires --runtime-variant installed and an installed root or archive")


INSTALLED_PARSE = """
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root))
from belay.sqlite.dialects import ProfileIdentity
from belay.sqlite.parser_library import installed_library, load
from belay.sqlite.profiles import profile
from belay.sqlite.sql_tree import SqlParser, parse
selected = profile(sys.argv[2])
parser = SqlParser.for_profile(load(installed_library(root, sys.platform)),
                               ProfileIdentity(selected.engine, selected.source_id))
tree = parse(parser, (root / "examples/approved/schema.sql").read_bytes(), "schema.sql")
print(json.dumps({"grammar": parser.grammar, "nodes": len(tree.nodes)}))
"""
"""Parse the installed example schema with the installed binding and parser library."""


@pytest.mark.parametrize("version", ["3.51.0", "3.46.0"])
def test_installed_parser(version: str, runtime_root: Path, tmp_path: Path,
                          command_runner: Callable[..., CommandResult]) -> None:
    """The installed parser library parses with each supported profile's grammar under
    poisoned ambient imports, loaded only from the installed path."""
    result = command_runner([sys.executable, "-I", "-c", INSTALLED_PARSE, str(runtime_root.resolve()), version],
                            cwd=tmp_path, timeout=10)
    assert result.returncode == 0, result.diagnostic()
    assert result.json_object()["nodes"] > 0, result.diagnostic()


@pytest.fixture
def installed_verify(runtime_root: Path, tmp_path: Path,
                     command_runner: Callable[..., CommandResult]) -> Callable[..., CommandResult]:
    """Bind installed examples and launcher together without importing checkout implementation."""
    def invoke(case: str, *, migration: Path | None = None, timeout: int = 180) -> CommandResult:
        """Verify an installed case with the inputs its `belay.toml` names; retain the installed deadlines."""
        examples = runtime_root / "examples"
        config = load(examples / case / "belay.toml", examples)
        arguments = config.contract_arguments()
        if migration is not None:
            arguments[arguments.index("--migration") + 1] = str(migration)
        baseline = ["--approved-baseline", str(config.baseline)] if config.baseline is not None else []
        return command_runner([str(runtime_root / "bin/migration-check"), "verify", "--format", "json",
                               *arguments, *config.candidate_arguments(), *baseline], cwd=tmp_path, timeout=timeout)
    return invoke


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    """Run `test_installed_case_status` once for each checked-in case of the `cli` target.

    The names come from the selected runtime root, or from the checkout when an
    archive is installed during the run.
    """
    if "case_name" in metafunc.fixturenames:
        examples = (metafunc.config.getoption("runtime_root") or metafunc.config.rootpath) / "examples"
        metafunc.parametrize("case_name", case_names(examples, "cli"))


def test_installed_case_status(case_name: str, runtime_root: Path,
                               installed_verify: Callable[..., CommandResult]) -> None:
    """The installed entrypoint gives each shipped case the status its `belay.toml` expects."""
    expected = load(runtime_root / "examples" / case_name / "belay.toml", runtime_root / "examples").test_status
    result = installed_verify(case_name)
    assert result.json_object()["status"] == expected, result.diagnostic()
    assert result.returncode == (0 if expected == "VERIFIED" else 1), result.diagnostic()


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
                             example_factory: Callable[[str], Path], candidate: str, checked_migration: str | None,
                             status: str) -> None:
    """The installed `prepare` and `verify-bundle` reproduce the source statuses under poisoned imports.

    `prepare` builds the case's proofs project, so it runs on a private copy of the installed examples.
    """
    examples = example_factory(".")
    launcher = str(runtime_root / "bin/migration-check")

    def common(migration: str) -> list[str]:
        """Contract and SQL arguments for the shipped approved example."""
        return ["--profile", "3.51.0", "--format", "json", "--schema", str(examples / "approved/schema.sql"),
                "--requirements", str(examples / "approved/Requirements.lean"),
                "--interpretation", str(examples / "approved/Interpretation.lean"),
                "--migration", str(examples / migration / "migration.sql")]

    bundle = tmp_path / "proof.bundle"
    prepared = command_runner([launcher, "prepare", *common(candidate), "--project", str(examples / candidate),
                               "--output", str(bundle)], cwd=tmp_path, timeout=180)
    assert prepared.returncode == 0 and prepared.json_object()["status"] == "PREPARED", prepared.diagnostic()
    checked = command_runner([launcher, "verify-bundle", *common(checked_migration or candidate),
                              "--bundle", str(bundle)], cwd=tmp_path, timeout=120)
    assert checked.json_object()["status"] == status, checked.diagnostic()
    assert checked.returncode == (0 if status == "VERIFIED" else 1), checked.diagnostic()


def test_installed_model_and_codec_consumer(runtime_root: Path, tmp_path: Path,
        command_runner: Callable[..., CommandResult]) -> None:
    """An unrelated installed consumer compiles core, codec and application imports from both roots."""
    source = tmp_path / 'NeutralConsumer.lean'
    source.write_text('import Belay.Sqlite\nimport Belay.Sqlite.Codec.Resolution\nimport SqliteVerifier\n'
        '#check Belay.Sqlite.Conforms.set\n#check Belay.Sqlite.TableExtends.project\n'
        '#check SqliteVerifier.VerificationConditions\n'
        'def record : Belay.Sqlite.ScriptRecord := ⟨3, "3.51.0", "build", [], []⟩\n'
        '#eval match Belay.Sqlite.decodeScriptRecord (Lean.toJson record) with\n'
        '  | .ok value => value.version == 3 && value.resolve.toOption.isSome\n  | .error _ => false\n')
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
from belay.sqlite.syntax import script_record
assert not (root / 'belay/__init__.py').exists()
assert {path.name for path in (root / 'belay').iterdir()} == {'sqlite'}
assert script_record(profile('3.46.0'), (), ())['release'] == '3.46.0'
assert not any(name.startswith('migration_check') for name in sys.modules)
print('INSTALLED_FRONTEND')
'''
    result = command_runner([python,'-I','-c',code,str(runtime_root)],cwd=tmp_path,timeout=15)
    assert result.returncode == 0 and result.stdout.strip() == 'INSTALLED_FRONTEND',result.diagnostic()
