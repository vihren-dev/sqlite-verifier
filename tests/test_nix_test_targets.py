"""Exercise Nix's real dependency identities and failed-test behavior, without receipt validation."""

import json
from pathlib import Path
import shutil
import shlex

import pytest

from tests.runtime_support import run_command

ROOT = Path(__file__).resolve().parents[1]
pytestmark = [pytest.mark.integration, pytest.mark.environment, pytest.mark.requires_nix]


def expression(root: Path) -> str:
    """Reuse the actual test definitions with a private source tree and unchanged runtime dependencies."""
    quote = lambda path: json.dumps(str(path)).replace("${", "\\${")
    return f'''let
      pkgs = import (builtins.toPath {quote(ROOT / 'build-support/locked-nixpkgs.nix')}) {{}};
      builds = import (builtins.toPath {quote(ROOT / 'build-support/default.nix')}) {{}};
    in import (builtins.toPath {quote(ROOT / 'build-support/tests.nix')}) {{
      inherit pkgs; inherit (builds) leanToolchain leanRuntime parsers conformance;
      runtime = import (builtins.toPath {quote(ROOT / 'build-support/runtime.nix')}) {{
        inherit pkgs; inherit (builds) leanToolchain leanRuntime parsers;
        sources = builds.sources // {{ runtime = (import (builtins.toPath {quote(ROOT / 'build-support/sources.nix')}) {{
          inherit (pkgs) lib; root = /. + {quote(root)};
        }}).runtime; }};
      }};
      root = /. + {quote(root)};
    }}'''


def identities(root: Path) -> dict[str, str]:
    """Evaluate derivation paths, which include sources, commands and all declared tool dependencies."""
    result = run_command(['nix-instantiate', '--eval', '--strict', '--json',
        '--extra-experimental-features', 'nix-command flakes', '--expr',
        f'builtins.mapAttrs (_: test: test.drvPath) ({expression(root)})'], cwd=ROOT, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    return json.loads(result.stdout)


def test_bounded_commands_keep_complete_suite_ownership() -> None:
    """The real Nix command runs every owned file with a per-test limit and full reporting."""
    result = run_command(['nix-instantiate', '--eval', '--strict', '--json',
        '--extra-experimental-features', 'nix-command flakes', '--expr',
        f'builtins.mapAttrs (_: test: test.installPhase) ({expression(ROOT)})'], cwd=ROOT, timeout=30)
    assert result.returncode == 0, result.diagnostic()
    scripts = json.loads(result.stdout)
    ownership = json.loads((ROOT / 'tests/nix_suites.json').read_text())
    assert set(scripts) == set(ownership) == {'atuin', 'bundle', 'cli', 'kernel', 'model', 'frozen',
                                               'harness', 'sample', 'upstream'}
    for name, script in scripts.items():
        command = shlex.split(next(line for line in script.replace('\\\n', ' ').splitlines()
                                  if line.strip().startswith('timeout ')))
        assert command[:5] == ['timeout', '1200', 'python3', '-m', 'pytest']
        runtime_index = command.index('--runtime-root')
        assert command[5:runtime_index] == ownership[name], (name, command)
        assert command[runtime_index + 2:] == ['-p', 'no:cacheprovider', '-p', 'pytest_timeout', '--timeout=300',
            '--junitxml', '$out/junit.xml', '-v', '--durations=10'], (name, command)


@pytest.fixture
def source_tree(tmp_path: Path) -> Path:
    """Copy only small potential test inputs; no store outputs, vendored parsers or build trees."""
    for name in ('pytest.ini', 'conftest.py', 'LICENSE'):
        shutil.copy2(ROOT / name, tmp_path / name)
    for name in ('tests', 'migration_check', 'conformance', 'examples', 'docs', 'packaging', 'SqliteVerifier', 'VerifierConformance', 'reports', 'nix', 'build-support', 'tools'):
        shutil.copytree(ROOT / name, tmp_path / name,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'upstream'))
    return tmp_path


@pytest.mark.parametrize('relative,affected', [
    ('tests/kernel_gate_test.py', {'kernel'}),
    ('tests/single_executor_test.py', {'kernel'}),
    ('tests/kernel_gate/Proofs.lean', {'kernel', 'bundle'}),
    ('tests/kernel_fixture.py', {'kernel', 'bundle'}),
    ('tests/kernel_attack_cases.py', {'kernel', 'bundle'}),
    ('tests/bundle_attack_test.py', {'bundle'}),
    ('tests/bundle_attack_fixture.py', {'bundle'}),
    ('tests/bundle_hostile_records.py', {'bundle'}),
    ('conformance/model_cases.py', {'model', 'frozen', 'harness', 'upstream'}),
    ('conformance/replay_tiers.py', {'model', 'frozen', 'harness', 'sample', 'upstream'}),
    ('conformance/corpus-v5/manifest.json', {'frozen', 'sample'}),
    ('conformance/corpus-v4/manifest.json', {'frozen', 'upstream'}),
    ('conformance/corpus-v3/manifest.json', {'frozen', 'upstream'}),
    ('conformance/corpus-v2/manifest.json', {'frozen', 'upstream'}),
    ('conformance/corpus-v1/manifest.json', {'frozen', 'upstream'}),
    ('reports/20261001-adr5-c4-fidelity.json', {'frozen'}),
    ('conformance/requirements-3.51.0.json', {'model', 'frozen', 'harness', 'upstream'}),
    ('tools/__init__.py', {'upstream'}),
    ('tools/check_resources.py', {'upstream'}),
    ('nix/flake.nix', {'upstream'}),
    ('nix/flake.lock', {'model', 'frozen', 'harness', 'upstream'}),
    ('nix/sqlite.nix', {'model', 'frozen', 'harness', 'upstream'}),
    ('build-support/conformance-native.nix', {'model', 'frozen', 'harness', 'upstream'}),
    ('conformance/synthetic-workload/workload.json', {'model', 'frozen', 'harness', 'sample'}),
    ('conformance/progress.py', {'model', 'frozen', 'harness', 'upstream'}),
    ('tests/conformance_sample_test.py', {'sample'}),
    ('tests/conformance_tier_bindings_test.py', {'frozen'}),
    ('tests/conformance_authored_test.py', {'frozen'}),
    ('tests/conformance_storage_test.py', {'harness'}),
    ('tests/conformance_authored_transactions_test.py', {'harness'}),
    ('tests/conformance_transaction_evidence_test.py', {'frozen'}),
    ('conformance/authored_transactions.py', {'model', 'frozen', 'harness', 'upstream'}),
    ('conformance/transaction_evidence.py', {'model', 'frozen', 'harness', 'upstream'}),
    ('reports/20261006-grouped-immediate-transactions/manifest.json', {'frozen'}),
    ('reports/20261006-grouped-immediate-transactions/shards/0000.jsonl.gz', {'frozen'}),
    ('tests/conformance_freeze_test.py', {'frozen', 'upstream'}),
    ('tests/conformance_command_sources_test.py', {'upstream'}),
    ('tests/test_native_replay_storage.py', {'upstream'}),
    ('tests/conformance_foreign_key_recovery_test.py', {'upstream'}),
    ('conformance/cases/add_then_create.json', {'model', 'frozen', 'harness', 'bundle'}),
    ('conformance/native_trace.py', {'model', 'frozen', 'harness', 'sample', 'upstream'}),
    ('conformance/native_acquisition.py', {'model', 'frozen', 'harness', 'sample', 'upstream'}),
    ('conformance/case_format.py', {'model', 'frozen', 'harness', 'sample', 'upstream'}),
    ('VerifierConformance/Trace.lean', {'model', 'frozen', 'harness'}),
    ('tests/conformance_pipeline_test.py', {'model'}),
    ('migration_check/translate.py', {'model', 'frozen', 'harness', 'sample', 'upstream', 'atuin', 'cli', 'bundle'}),
    ('migration_check/prepare.py', {'atuin', 'cli', 'bundle'}),
    ('conftest.py', {'kernel', 'model', 'frozen', 'harness', 'sample', 'upstream', 'atuin', 'cli', 'bundle'}),
    ('tests/atuin_cli_test.py', {'atuin'}),
    ('tests/cli_test.py', {'cli'}),
    ('tests/bundle_test.py', {'bundle'}),
    ('tests/generated_inputs_test.py', {'bundle'}),
    ('examples/atuin/Proofs.lean', {'atuin', 'cli', 'bundle'}),
    ('tests/test_translation.py', set()),
])
def test_dependency_invalidation(source_tree: Path, relative: str, affected: set[str]) -> None:
    """Changing a declared input invalidates only dependent suites; unrelated tests leave both cached."""
    before = identities(source_tree)
    path = source_tree / relative
    path.write_bytes(path.read_bytes() + b'\n')
    after = identities(source_tree)
    assert {name for name in before if before[name] != after[name]} == affected


def test_failed_pytest_target_has_no_output(source_tree: Path) -> None:
    """A real sandboxed target with a failed pytest assertion cannot create a reusable successful output."""
    (source_tree / 'tests/kernel_gate_test.py').write_text('''import pytest
pytestmark = [pytest.mark.integration, pytest.mark.kernel]
def test_failure():
    """Deliberate failure must propagate through the Nix build."""
    assert False, "intentional pytest failure"
''')
    result = run_command(['nix-build', '--no-out-link', '--option', 'sandbox', 'true',
        '--option', 'sandbox-fallback', 'false', '--extra-experimental-features', 'nix-command flakes',
        '--expr', f'({expression(source_tree)}).kernel'], cwd=ROOT, timeout=90)
    assert result.returncode != 0, result.diagnostic()
    assert 'intentional pytest failure' in result.stderr, result.diagnostic()


@pytest.fixture(scope="session")
def flake_source(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Nix 2.18 needs a Git source boundary for a subdirectory flake, including in jj workspaces."""
    destination = tmp_path_factory.mktemp("flake-source") / "checkout"
    shutil.copytree(ROOT, destination, symlinks=True, ignore=shutil.ignore_patterns(
        ".git", ".jj", ".lake", ".direnv", ".pytest_cache", "build", "dist", "lean",
        "result*", "__pycache__", "*.pyc"))
    for command in (["git", "init", "-q"], ["git", "add", "."]):
        result = run_command(command, cwd=destination, timeout=30)
        assert result.returncode == 0, result.diagnostic()
    return destination


@pytest.mark.parametrize('system', ['aarch64-darwin', 'x86_64-linux'])
def test_flake_checks_reuse_existing_targets(system: str, flake_source: Path) -> None:
    """Flake checks expose the same derivations as the legacy entrypoint, preserving cached results."""
    flags = ['--extra-experimental-features', 'nix-command flakes']
    projection = 'builtins.mapAttrs (_: test: test.drvPath)'
    flake = run_command(['nix', *flags, 'eval', '--json', '--no-update-lock-file',
                         f'git+file://{flake_source}?dir=nix#checks.{system}', '--apply', projection], cwd=ROOT, timeout=60)
    legacy = run_command(['nix-instantiate', *flags, '--eval', '--strict', '--json', '--expr',
        f'{projection} ((import ./build-support/default.nix {{ system = "{system}"; }}).tests)'],
        cwd=ROOT, timeout=60)
    assert flake.returncode == 0, flake.diagnostic()
    assert legacy.returncode == 0, legacy.diagnostic()
    checks = json.loads(flake.stdout)
    assert set(checks) == set(json.loads((ROOT / 'tests/nix_suites.json').read_text()))
    assert checks == json.loads(legacy.stdout)
