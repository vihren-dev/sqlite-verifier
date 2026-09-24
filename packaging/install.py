"""Copy a checked native payload and retain its pinned Nix runtime closure."""

from pathlib import Path
import shutil
import subprocess
import sys


def install(destination: Path) -> None:
    """Create one new installation and indirect GC roots without replacing existing files."""
    bundle = Path(__file__).resolve().parent
    destination = destination.expanduser().absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError("Installation directory already exists")
    roots = (bundle / "nix-paths").read_text().splitlines()
    destination.mkdir(parents=True, exist_ok=False)
    try:
        shutil.copytree(bundle / "payload", destination, symlinks=True, dirs_exist_ok=True)
        gc_roots = destination / ".nix-roots"
        gc_roots.mkdir()
        for root in roots:
            subprocess.run(["nix-store", "--add-root", str(gc_roots / Path(root).name),
                            "--indirect", "--realise", "--option", "substitute", "false",
                            "--option", "builders", "", "--option", "max-jobs", "0", root], check=True, timeout=30,
                           stdout=subprocess.DEVNULL)
    except BaseException:
        if destination.is_dir():
            shutil.rmtree(destination)
        raise
    print(f"Installed: {destination / 'bin/migration-check'}")
    print(f"Examples: {destination / 'examples'}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Expected a new installation directory")
    install(Path(sys.argv[1]))
