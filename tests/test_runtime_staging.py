"""Archive staging reads one explicit immutable runtime and writes only its destination."""

from pathlib import Path
import sys
import tarfile
from types import SimpleNamespace
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "packaging"))
import build_runtime

pytestmark = [pytest.mark.unit, pytest.mark.packaging]


def write(root: Path, name: str, content: str = "fixture") -> Path:
    """Create tiny distinguishable inputs without building native artifacts."""
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path


def test_explicit_runtime_archive_uses_current_modules_and_interpreter(tmp_path: Path) -> None:
    """Explicit runtime inputs survive staging while stale modules and checkout files do not."""
    root = tmp_path / "runtime ü space"
    for name in ("migration_check/cli.py", "examples/example.sql", "docs/install.md",
                 "LICENSE", "lean-toolchain", "Current.lean", "SqliteVerifier/Current.lean",
                 ".lake/build/lib/lean/Current.olean", ".lake/build/lib/lean/Current.olean.private",
                 ".lake/build/lib/lean/SqliteVerifier/Current.olean",
                 ".lake/build/lib/lean/Deleted.olean", "build/sqlite-parser",
                 "build/sqlite-parser-3.46.0", ".lake/build/bin/migration-proof-checker",
                 "lean/bin/lean", "lean/LICENSE", "lean/LICENSES", "lean/lib/lean/Init.olean",
                 "packaging/install.py", "packaging/install.sh"):
        write(root, name, name)
    python = write(tmp_path, "bare-python/bin/python3")
    output = tmp_path / "output ü space"
    commands: list[list[str]] = []

    def run(command: list[str], timeout: int = 30) -> str:
        """Mock only external tool execution; reject any ambient Lean lookup."""
        commands.append(command)
        if command == [str(root / "lean/bin/lean"), "--version"]:
            return "Lean (version 4.33.0, fixture)"
        assert command[0] == "nix", command
        assert "--offline" in command
        assert timeout == 300
        return ""

    with patch.object(build_runtime, "check_resources") as resources, \
         patch.object(build_runtime.shutil, "disk_usage", return_value=SimpleNamespace(free=20 * 1024**3)), \
         patch.object(build_runtime.platform, "system", return_value="Darwin"), \
         patch.object(build_runtime.platform, "machine", return_value="arm64"), \
         patch.object(build_runtime, "store_path", return_value=Path("/nix/store/python-fixture")), \
         patch.object(build_runtime, "native_dependencies", return_value=(set(), "loader fixture")) as native, \
         patch.object(build_runtime, "run", side_effect=run):
        archive = build_runtime.build(python, runtime_root=root, output_dir=output)
    resources.assert_called_once_with(build_runtime.ROOT)
    assert archive.parent == output
    assert not (root / "dist").exists()
    expected = [root / "build/sqlite-parser", root / ".lake/build/bin/migration-proof-checker",
                root / "build/sqlite-parser-3.46.0", root / "lean/bin/lean"]
    native.assert_called_once_with(expected, root / "lean")
    with tarfile.open(archive) as bundle:
        prefix = "sqlite-verifier-aarch64-darwin/"
        payload = prefix + "payload/"
        names = bundle.getnames()
        assert payload + ".lake/build/lib/lean/Current.olean" in names
        assert payload + ".lake/build/lib/lean/Current.olean.private" in names
        assert payload + ".lake/build/lib/lean/Deleted.olean" not in names
        launcher = bundle.extractfile(payload + "bin/migration-check")
        assert launcher is not None and launcher.read().decode().startswith(f"#!{python} -I\n")
        example = bundle.extractfile(payload + "examples/example.sql")
        assert example is not None and example.read() == b"examples/example.sql"
        interpreter = bundle.extractfile(prefix + "python-path")
        assert interpreter is not None and interpreter.read().decode() == str(python) + "\n"
    assert archive.with_suffix(".gz.sha256").is_file()
    assert any("?compression=zstd" in part for command in commands for part in command)
    assert any("--sigs-needed" in command for command in commands)


def test_missing_current_module_rejects_stale_artifact(tmp_path: Path) -> None:
    """An unrelated stale compiled module cannot satisfy a current source module."""
    write(tmp_path, "Current.lean")
    write(tmp_path, ".lake/build/lib/lean/Deleted.olean")
    with pytest.raises(ValueError, match="Current module has not been built"):
        build_runtime.project_runtime_files(tmp_path)


def test_explicit_runtime_never_falls_back_to_ambient_lean(tmp_path: Path) -> None:
    """A missing supplied toolchain is an error before external Lean can be consulted."""
    python = write(tmp_path, "python3")
    with patch.object(build_runtime, "check_resources"), \
         patch.object(build_runtime.shutil, "disk_usage", return_value=SimpleNamespace(free=20 * 1024**3)), \
         patch.object(build_runtime.platform, "system", return_value="Darwin"), \
         patch.object(build_runtime.platform, "machine", return_value="arm64"), \
         patch.object(build_runtime, "store_path", return_value=Path("/nix/store/python-fixture")), \
         patch.object(build_runtime, "run") as run:
        with pytest.raises(FileNotFoundError):
            build_runtime.build(python, runtime_root=tmp_path, output_dir=tmp_path / "output")
        run.assert_not_called()


@pytest.mark.parametrize("destination,free,message", [
    ("output", 0, "10 GiB"),
    ("/nix/store/forbidden-archive", 20 * 1024**3, "immutable Nix store"),
])
def test_archive_output_preflight_precedes_tool_reads(
    tmp_path: Path, destination: str, free: int, message: str,
) -> None:
    """A separate full filesystem or immutable output stops before inspecting tools."""
    output = tmp_path / destination
    with patch.object(build_runtime, "check_resources"), \
         patch.object(build_runtime.shutil, "disk_usage", return_value=SimpleNamespace(free=free)), \
         patch.object(build_runtime, "run") as run:
        with pytest.raises(ValueError, match=message):
            build_runtime.build(tmp_path / "missing-python", runtime_root=tmp_path, output_dir=output)
        run.assert_not_called()
    assert not output.exists()
