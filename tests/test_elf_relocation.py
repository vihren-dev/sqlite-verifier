"""Copied ELF objects resolve bundled libraries locally while retaining signed external dependencies."""

from pathlib import Path
import stat
import sys
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "packaging"))
from relocate_elf import relocate_elf, staged_reference

pytestmark = [pytest.mark.unit, pytest.mark.packaging]


@pytest.fixture
def trees(tmp_path: Path) -> tuple[Path, Path, Path]:
    """Create distinct immutable-input and writable-stage layouts without native executables."""
    source, staged = tmp_path / "source-lean", tmp_path / "payload/lean"
    for root in (source, staged):
        (root / "lib/lean").mkdir(parents=True)
        (root / "lib/lean/libLean.so").write_bytes(b"\x7fELFfixture")
    binary = staged / "bin/lean"
    binary.parent.mkdir()
    binary.write_bytes(b"\x7fELFfixture")
    return source, staged, binary


@pytest.mark.parametrize("reference", ["/nix/store/signed-glibc/lib", "$ORIGIN/../lib", "libc.so.6"])
def test_external_or_relative_references_remain_unchanged(trees: tuple[Path, Path, Path], reference: str) -> None:
    """Only bundled absolute references change; existing signed and relative loader identities survive."""
    source, staged, binary = trees
    assert staged_reference(reference, binary, source, staged) == reference


@pytest.mark.parametrize("problem", ["missing", "parent", "symlink"])
def test_bundled_reference_must_exist_inside_stage(trees: tuple[Path, Path, Path], problem: str) -> None:
    """Missing or escaping staged targets cannot be silently retained as original store dependencies."""
    source, staged, binary = trees
    if problem == "missing":
        reference = source / "lib/absent.so"
        error = FileNotFoundError
    elif problem == "parent":
        reference = source / "../lean"
        error = ValueError
    else:
        (staged / "lib/escape").symlink_to(source / "lib/lean")
        reference = source / "lib/escape/libLean.so"
        error = ValueError
    with pytest.raises(error):
        staged_reference(str(reference), binary, source, staged)


def test_rpath_and_needed_relocate_all_copied_elf_objects(trees: tuple[Path, Path, Path]) -> None:
    """Lean, its shared library and the checker map RPATH/NEEDED without modifying source bytes or modes."""
    source, staged, lean = trees
    library = staged / "lib/lean/libLean.so"
    checker = staged.parent / ".lake/build/bin/migration-proof-checker"
    checker.parent.mkdir(parents=True)
    checker.write_bytes(b"\x7fELFchecker")
    text = staged / "lib/lean/Module.olean"
    text.write_bytes(b"not ELF")
    binaries = [lean, library, checker]
    for binary in binaries:
        binary.chmod(0o555)
    commands: list[list[str]] = []

    def run(command: list[str]) -> str:
        """Supply loader metadata and record mutations without requiring a host ELF loader."""
        commands.append(command)
        if command[1] == "--print-rpath":
            return f"{source}/lib/lean:/nix/store/signed-glibc/lib:$ORIGIN/../lib"
        if command[1] == "--print-needed":
            return f"{source}/lib/lean/libLean.so\nlibc.so.6\n"
        assert Path(command[-1]).stat().st_mode & stat.S_IWUSR
        return ""

    with patch("relocate_elf.run", side_effect=run):
        relocate_elf([*binaries, text], source, staged)
    for binary in binaries:
        expected = staged_reference(str(source / "lib/lean"), binary, source, staged)
        assert ["patchelf", "--set-rpath", expected + ":/nix/store/signed-glibc/lib:$ORIGIN/../lib", str(binary)] in commands
        needed_target = {lean: "$ORIGIN/../lib/lean/libLean.so", library: "$ORIGIN/libLean.so",
                         checker: "$ORIGIN/../../../lean/lib/lean/libLean.so"}[binary]
        assert ["patchelf", "--replace-needed", str(source / "lib/lean/libLean.so"),
                needed_target, str(binary)] in commands
        assert stat.S_IMODE(binary.stat().st_mode) == 0o555
    assert not any(command[-1] == str(text) for command in commands)
    assert (source / "lib/lean/libLean.so").read_bytes() == b"\x7fELFfixture"
