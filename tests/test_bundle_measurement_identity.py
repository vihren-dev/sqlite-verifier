"""Cold-run identities detect actual byte/link/mode changes and refuse populated caches."""

import hashlib
from pathlib import Path

import pytest

from tools.bundle_measurement_identity import empty_cache_directory, evidence_identity, host_conditions, host_identity, tree_identity


def test_exact_file_bytes_and_modes(tmp_path: Path) -> None:
    """Identity hashing preserves NUL/non-ASCII bytes and notices executable permission changes."""
    path = tmp_path / "source"
    path.write_bytes(b"\x00\xff" + "λ".encode())
    before = tree_identity(path)
    assert before["files"]["."]["sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()
    assert before == tree_identity(path)
    path.write_bytes(b"\x00\xfe" + "λ".encode())
    assert before != tree_identity(path)
    before = tree_identity(path)
    path.chmod(path.stat().st_mode | 0o100)
    assert before != tree_identity(path)


def test_follow_actual_installed_links_and_cycles(tmp_path: Path) -> None:
    """The installed tree binds linked compiler bytes while directory cycles terminate deterministically."""
    runtime, toolchain = tmp_path / "runtime", tmp_path / "toolchain"
    runtime.mkdir()
    toolchain.mkdir()
    (toolchain / "lean").write_bytes(b"actual pinned compiler")
    (runtime / "lean").symlink_to(toolchain, target_is_directory=True)
    (toolchain / "back").symlink_to(runtime, target_is_directory=True)
    before = tree_identity(runtime)
    assert set(before["files"]) == {"lean/lean"}
    assert set(before["directory_references"]) == {".", "lean", "lean/back"}
    (toolchain / "lean").write_bytes(b"other compiler")
    assert before != tree_identity(runtime)


def test_selected_runtime_sources_observer_and_python_all_bound(tmp_path: Path) -> None:
    """The recorder cannot substitute one implementation component while keeping its run identity."""
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    files = [tmp_path / name for name in ("inputs", "observer.py", "python")]
    for file in files:
        file.write_bytes(b"same initial bytes")
    first = evidence_identity(runtime, files[:1], files[1], files[2])
    for file in [*files, runtime / "module"]:
        file.write_bytes(b"changed")
        assert first != evidence_identity(runtime, files[:1], files[1], files[2])
        file.write_bytes(b"same initial bytes")
        if file.parent == runtime:
            file.unlink()
    assert first == evidence_identity(runtime, files[:1], files[1], files[2])


def test_empty_cache_is_new_and_never_cleaned(tmp_path: Path) -> None:
    """A warm or preexisting directory remains intact as evidence of an invalid cold trial."""
    cache = empty_cache_directory(tmp_path, "cache")
    assert cache.is_absolute() and not list(cache.iterdir())
    with pytest.raises(ValueError, match="already exists"):
        empty_cache_directory(tmp_path, "cache")
    (cache / "proof.olean").write_bytes(b"warm")
    with pytest.raises(ValueError, match="already exists"):
        empty_cache_directory(tmp_path, "cache")
    assert (cache / "proof.olean").read_bytes() == b"warm"


def test_cache_conditions_state_observation_limits() -> None:
    """Recorded OS-cache/load conditions cannot imply forcibly flushed or observed residency."""
    conditions = host_conditions()
    assert conditions["os_file_caches"] == "not flushed; file residency is not observed"
    assert "before and after each path" in conditions["identity_reads"]
    assert "individual process activity is not observed" in conditions["background_processes"]


def test_platform_machine_cpu_identity_fields() -> None:
    """A campaign records the actual machine and Python identities independently of changing load."""
    identity = host_identity()
    assert set(identity) == {"system", "release", "machine", "node", "cpu_count", "python"}
    assert all(isinstance(identity[key], str) for key in identity if key != "cpu_count")
    assert identity["cpu_count"] is None or type(identity["cpu_count"]) is int
    assert identity["system"] and identity["machine"] and identity["python"]


def test_measurement_policy_source_changes_are_identity_bound(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A changed acquisition/statistics implementation cannot reuse the same campaign identity."""
    import tools.bundle_measurement_identity as identities
    tools = tmp_path / "tools"
    tools.mkdir()
    module = tools / "bundle_measurement_identity.py"
    module.write_bytes(b"fixture identity implementation")
    monkeypatch.setattr(identities, "__file__", str(module))
    first = evidence_identity(tools, (), module, module)
    policy = tools / "bundle_measurement_statistics.py"
    policy.write_bytes(b"changed statistics policy")
    assert first != evidence_identity(tools, (), module, module)
    assert str(policy) in evidence_identity(tools, (), module, module)["measurement_sources"]
