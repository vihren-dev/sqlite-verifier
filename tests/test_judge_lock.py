"""The judge lock and prediction inputs (`integrity/judge.nix`), ADR 0011.

The lock makes a change to the judge, its claims, a claimed corpus or the native SQLite
oracle impossible without a change to the code-owned lock file. These tests change one byte
of each part in a temporary copy of the repository, with corpus v1 as the only claim, and
check that Nix evaluation stops and names that part, and passes again when it is restored.
Prediction identity checks add minimal Python sources and a fixed runtime stub to that
copy. They evaluate the production judge expression without building a runtime or predictions.
"""

import json
from pathlib import Path
import shutil
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
NIX_TIMEOUT_SECONDS = 120
"""One evaluation of the lock over a small copy."""
COPIED = ["integrity/judge.nix", "nix/sqlite.nix", "nix/flake.lock", "judge",
          "conformance/corpus-v1"]
"""The files that the lock check reads."""

pytestmark = [pytest.mark.integration, pytest.mark.requires_nix]


def evaluate(tree: Path, attribute: str) -> subprocess.CompletedProcess[str]:
    """Evaluate one attribute of the copied `integrity/judge.nix`."""
    return subprocess.run(["nix-instantiate", "--eval", "--strict", "--json", str(tree / "integrity/judge.nix"), "-A", attribute],
                          capture_output=True, text=True, timeout=NIX_TIMEOUT_SECONDS, check=False)


@pytest.fixture(scope="module")
def tree(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """A copy of the lock's inputs, claiming only corpus v1, with a lock of its current values."""
    copy = tmp_path_factory.mktemp("judge-lock")
    for relative in COPIED:
        source, target = ROOT / relative, copy / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        (shutil.copytree if source.is_dir() else shutil.copy2)(source, target)
    claims = {"corpora": {"corpus-v1": {"path": "conformance/corpus-v1", "mustAgree": [],
                                         "forbidden": ["DISAGREE", "HARNESS_ERROR"]}}}
    (copy / "judge/claims.json").write_text(json.dumps(claims))
    (copy / "integrity/judge.lock.json").write_text("{}")
    current = evaluate(copy, "current")
    assert current.returncode == 0, current.stderr
    (copy / "integrity/judge.lock.json").write_text(current.stdout)
    return copy


@pytest.mark.parametrize("relative,part", [
    ("conformance/corpus-v1/manifest.json", "corpus corpus-v1"),
    ("judge/claims.json", "judge"),
    ("judge/compare.py", "judge"),
    ("nix/sqlite.nix", "oracle"),
])
def test_a_changed_part_stops_evaluation(tree: Path, relative: str, part: str) -> None:
    """`integrity/judge.nix` `locked`: one changed byte in a part stops evaluation and names the part;
    the restored part passes again."""
    assert evaluate(tree, "locked").returncode == 0
    path = tree / relative
    original = path.read_bytes()
    path.write_bytes(original + b" ")
    try:
        changed = evaluate(tree, "locked")
        assert changed.returncode != 0
        assert f"the judge changed: {part} differs from integrity/judge.lock.json" in changed.stderr
    finally:
        path.write_bytes(original)
    assert evaluate(tree, "locked").returncode == 0


def test_an_unknown_lock_entry_stops_evaluation(tree: Path) -> None:
    """`integrity/judge.nix` `locked`: a lock entry for a part that the claims no longer name is a change."""
    lock = tree / "integrity/judge.lock.json"
    original = lock.read_text()
    lock.write_text(json.dumps({**json.loads(original), "corpus removed": "/nix/store/x"}))
    try:
        assert "corpus removed differs" in evaluate(tree, "locked").stderr
    finally:
        lock.write_text(original)


def test_files_left_by_running_the_judge_do_not_change_the_lock(tree: Path) -> None:
    """`integrity/judge.nix` `locked`: a `__pycache__` file, as running the judge leaves it, does
    not change the judge part, so a working copy and a fresh checkout have one lock."""
    cache = tree / "judge/__pycache__/compare.cpython-314.pyc"
    cache.parent.mkdir(exist_ok=True)
    cache.write_bytes(b"compiled")
    try:
        assert evaluate(tree, "locked").returncode == 0
    finally:
        shutil.rmtree(cache.parent)


@pytest.fixture
def prediction_tree(tree: Path, tmp_path: Path) -> Path:
    """Extend the small lock fixture with Python inputs and a runtime that is never executed."""
    copy = tmp_path / "predictions"
    shutil.copytree(tree, copy)
    for relative, text in {
        "belay/sqlite/profiles.py": "value = 1\n",
        "conformance/predict.py": "value = 1\n",
        "build-support/default.nix": '{ system }: { conformance = "/stub-runtime"; }\n',
    }.items():
        path = copy / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return copy


def prediction_identity(tree: Path) -> str:
    """Read the actual prediction derivation identity without building its inputs or output."""
    result = evaluate(tree, "predictions.drvPath")
    assert result.returncode == 0, result.stderr
    identity = json.loads(result.stdout)
    assert isinstance(identity, str) and identity.endswith(".drv"), identity
    return identity


def test_frontend_bytecode_does_not_change_predictions(prediction_tree: Path) -> None:
    """The predictor's source filter ignores added, edited and removed frontend bytecode,
    which previously rebuilt predictions after Python runs without source changes."""
    before = prediction_identity(prediction_tree)
    cache = prediction_tree / "belay/sqlite/__pycache__/profiles.cpython-314.pyc"
    cache.parent.mkdir()
    for content in (b"compiled", b"recompiled"):
        cache.write_bytes(content)
        assert prediction_identity(prediction_tree) == before
    cache.unlink()
    assert prediction_identity(prediction_tree) == before


@pytest.mark.parametrize("relative", ["belay/sqlite/profiles.py", "conformance/predict.py"])
def test_python_source_changes_predictions(prediction_tree: Path, relative: str) -> None:
    """The predictor's source filter retains both Python components, so a real source edit
    changes the derivation identity and restoring that source restores the identity."""
    before = prediction_identity(prediction_tree)
    source = prediction_tree / relative
    original = source.read_bytes()
    source.write_bytes(original + b"value = 2\n")
    assert prediction_identity(prediction_tree) != before
    source.write_bytes(original)
    assert prediction_identity(prediction_tree) == before
