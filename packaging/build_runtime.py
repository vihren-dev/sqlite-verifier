"""Export one Nix runtime closure as a self-verifying offline installation archive."""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
from tempfile import TemporaryDirectory
from time import monotonic

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_resources import MIN_FREE_BYTES, check_resources, existing_parent


def run(arguments: list[str], timeout: int = 300) -> str:
    """Bound packaging tools and preserve their diagnostics on failure."""
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{arguments}: {result.stdout}{result.stderr}")
    return result.stdout


def store_runtime(path: Path) -> Path:
    """Package a built immutable runtime, never reconstruct one from checkout artifacts."""
    root = path.resolve(strict=True)
    if root.parent != Path('/nix/store') or not (root / 'bin/migration-check').is_file():
        raise ValueError(f"Expected a Nix runtime output: {root}; run just build")
    return root


def build(runtime_root: Path, *, output_dir: Path | None = None) -> Path:
    """Keep Nix content verification enabled, including for locally built project outputs."""
    check_resources(ROOT)
    dist = (output_dir if output_dir is not None else ROOT / 'dist').resolve()
    if dist.is_relative_to(Path('/nix/store')):
        raise ValueError(f"Archive output must be outside the immutable Nix store: {dist}")
    if shutil.disk_usage(existing_parent(dist)).free < MIN_FREE_BYTES:
        raise ValueError(f"At least 10 GiB free is required for archive output: {dist}")
    root = store_runtime(runtime_root)
    system = {('Darwin', 'arm64'): 'aarch64-darwin', ('Linux', 'x86_64'): 'x86_64-linux'}[
        (platform.system(), platform.machine())]
    if (root / 'platform').read_text().strip() != system:
        raise ValueError('Runtime platform differs from the packaging host')
    nix = ['nix', '--extra-experimental-features', 'nix-command', '--offline']
    started = monotonic()
    rewrites = json.loads(run([*nix, 'store', 'make-content-addressed', '--json', str(root)]))['rewrites']
    addressed = store_runtime(Path(rewrites[str(root)]))
    print(f'Runtime content addressing: {monotonic() - started:.2f}s', flush=True)
    dist.mkdir(parents=True, exist_ok=True)
    archive = dist / f'sqlite-verifier-{system}.tar.gz'
    with TemporaryDirectory(prefix='runtime-bundle-') as temporary:
        # Keep the whole closure live until its offline cache is complete.
        run(['nix-store', '--add-root', str(Path(temporary) / 'runtime-root'), '--indirect',
             '--realise', '--option', 'substitute', 'false', '--option', 'builders', '',
             '--option', 'max-jobs', '0', str(addressed)])
        bundle = Path(temporary) / f'sqlite-verifier-{system}'
        bundle.mkdir()
        for name in ('install.sh', 'install.py'):
            shutil.copy2(addressed / 'packaging' / name, bundle / name)
        shutil.copy2(addressed / 'docs/install.md', bundle / 'README.md')
        for name in ('platform', 'python-path'):
            shutil.copy2(addressed / name, bundle / name)
        (bundle / 'runtime-path').write_text(str(addressed) + '\n')
        (bundle / 'nix-paths').write_text(str(addressed) + '\n')
        started = monotonic()
        run([*nix, 'copy', '--to', (bundle / 'nix-cache').as_uri() + '?compression=zstd', str(addressed)])
        run([*nix, 'store', 'verify', '--store', (bundle / 'nix-cache').as_uri(),
             '--all', '--sigs-needed', '1'])
        print(f'Runtime closure export and verification: {monotonic() - started:.2f}s', flush=True)
        started = monotonic()
        with tarfile.open(archive, 'w:gz', compresslevel=1) as output:
            output.add(bundle, arcname=bundle.name)
        print(f'Runtime archive compression: {monotonic() - started:.2f}s', flush=True)
    if archive.stat().st_size >= 2_000_000_000:
        raise ValueError('Archive exceeds the release asset size limit')
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    archive.with_suffix(archive.suffix + '.sha256').write_text(f'{digest}  {archive.name}\n')
    return archive


if __name__ == '__main__':
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument('--runtime-root', type=Path, default=ROOT / 'build/runtime',
                           help='Nix-built runtime output (default: build/runtime)')
    arguments.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    options = arguments.parse_args()
    print(build(options.runtime_root, output_dir=options.output_dir))
