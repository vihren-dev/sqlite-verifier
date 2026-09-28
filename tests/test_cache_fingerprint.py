"""Cache transport keys cover all declared source membership without checkout metadata."""

import json
from pathlib import Path
import subprocess
import sys

import pytest

from tools.cache_fingerprint import ENVIRONMENT_FILES, SOURCE_FILES, SOURCE_TREES, cache_keys

pytestmark = [pytest.mark.unit, pytest.mark.environment]


@pytest.fixture
def input_root(tmp_path: Path) -> Path:
    """Create minimal declared inputs; no Git, Nix or native build prerequisites."""
    for name in (*ENVIRONMENT_FILES, *SOURCE_FILES):
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(name)
    for name in SOURCE_TREES:
        (tmp_path / name).mkdir(exist_ok=True)
    return tmp_path


@pytest.mark.parametrize("relative", ENVIRONMENT_FILES)
def test_pin_changes_invalidate_compatible_prefix(input_root: Path, relative: str) -> None:
    """Every declared environment pin creates a different compatibility namespace."""
    before = cache_keys(input_root, "aarch64-darwin")
    path = input_root / relative
    path.write_text(path.read_text() + "changed")
    after = cache_keys(input_root, "aarch64-darwin")
    assert before["env_hash"] != after["env_hash"]
    assert before["prefix"] != after["prefix"]
    assert after["key"] == after["prefix"] + after["source_hash"]


@pytest.mark.parametrize("relative", [
    "Root.lean", "SqliteVerifier/New.lean", "parser/new_generator.py", "parser/upstream/new.h",
    "migration_check/new.py", "packaging/new.sh", "tools/new.py", "build-support/new.nix",
    "bin/new", "examples/new.sql", "tests/new-fixture.json", "tests/result-fixture.json",
    "conformance/new-fixture.test",
])
def test_source_membership_and_content_changes_invalidate_exact_key(input_root: Path, relative: str) -> None:
    """Add, edit, rename and delete each inventory category independently of Git tracking."""
    baseline = cache_keys(input_root, "x86_64-linux")
    path = input_root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("added")
    added = cache_keys(input_root, "x86_64-linux")
    assert added["source_hash"] != baseline["source_hash"]
    path.write_text("edited")
    edited = cache_keys(input_root, "x86_64-linux")
    assert edited["source_hash"] != added["source_hash"]
    renamed = path.with_name("renamed-" + path.name)
    path.rename(renamed)
    moved = cache_keys(input_root, "x86_64-linux")
    assert moved["source_hash"] != edited["source_hash"]
    assert moved["prefix"] == baseline["prefix"]
    renamed.unlink()
    assert cache_keys(input_root, "x86_64-linux") == baseline


def test_runtime_install_document_changes_but_unrelated_docs_do_not(input_root: Path) -> None:
    """Runtime install instructions are declared payload while general docs are not cached inputs."""
    baseline = cache_keys(input_root, "aarch64-darwin")
    (input_root / "docs/notes.md").write_text("unrelated")
    (input_root / "build-support/README.md").write_text("unrelated")
    assert cache_keys(input_root, "aarch64-darwin") == baseline
    (input_root / "docs/install.md").write_text("changed runtime input")
    assert cache_keys(input_root, "aarch64-darwin")["source_hash"] != baseline["source_hash"]


def test_generated_files_and_checkout_metadata_do_not_change_keys(input_root: Path) -> None:
    """Ignore root outputs and generated component subtrees in Git and Jujutsu workspaces."""
    baseline = cache_keys(input_root, "x86_64-linux")
    for directory in (".git", ".jj", ".lake", "build", "dist", "__pycache__"):
        for parent in (input_root, input_root / "examples", input_root / "tests"):
            path = parent / directory
            path.mkdir()
            (path / "generated.py").write_text("output")
    for name in ("tests/generated.pyc", "examples/.DS_Store", ".pytest_cache/report"):
        path = input_root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("output")
    (input_root / "result").symlink_to(input_root / "build", target_is_directory=True)
    assert cache_keys(input_root, "x86_64-linux") == baseline


def test_executable_modes_and_selected_symlinks_are_not_silently_ignored(input_root: Path) -> None:
    """Nix's executable bit changes identity; undeclared symlink targets fail explicitly."""
    path = input_root / "bin/tool"
    path.write_text("script")
    baseline = cache_keys(input_root, "x86_64-linux")
    path.chmod(0o755)
    assert cache_keys(input_root, "x86_64-linux")["source_hash"] != baseline["source_hash"]
    path.unlink()
    path.symlink_to(input_root / "LICENSE")
    with pytest.raises(ValueError, match="regular file"):
        cache_keys(input_root, "x86_64-linux")


def test_cli_outputs_are_canonical_and_safe_for_actions(input_root: Path) -> None:
    """A bounded subprocess emits identical JSON/action fields across repeated invocations."""
    output = input_root / "github-output"
    script = Path(__file__).resolve().parents[1] / "tools/cache_fingerprint.py"
    command = [sys.executable, str(script), "--root", str(input_root), "--system", "aarch64-darwin",
               "--github-output", str(output)]
    result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=10)
    keys = json.loads(result.stdout)
    assert keys == cache_keys(input_root, "aarch64-darwin")
    assert dict(line.split("=", 1) for line in output.read_text().splitlines()) == keys
    assert keys["prefix"] == f"build-v2-aarch64-darwin-{keys['env_hash']}-"
    assert cache_keys(input_root, "x86_64-linux")["source_hash"] == keys["source_hash"]
