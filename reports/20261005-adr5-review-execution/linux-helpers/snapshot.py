"""Export and receive only the exact owner-approved tracked public commit."""

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile


def digest(data: bytes) -> str:
    """Bind transport bytes and regular source files independently."""
    return hashlib.sha256(data).hexdigest()


def public_files(archive: bytes) -> list[tuple[str, bytes, int]]:
    """Refuse VCS state, build output, private paths and nonregular archive entries."""
    files: list[tuple[str, bytes, int]] = []
    names: set[str] = set()
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:') as reader:
        for member in reader.getmembers():
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or str(path) != member.name.rstrip('/')
                    or path.parts[0] in {'.git', '.jj', 'build', 'private'}):
                raise ValueError('Nonpublic archive path: ' + member.name)
            if member.isdir():
                continue
            if not member.isfile() or member.name in names:
                raise ValueError('Nonregular or duplicate archive entry: ' + member.name)
            names.add(member.name)
            stream = reader.extractfile(member)
            if stream is None:
                raise ValueError('Unreadable archive entry: ' + member.name)
            files.append((member.name, stream.read(), 0o755 if member.mode & 0o111 else 0o644))
    if not files:
        raise ValueError('Empty public snapshot')
    return files


def main() -> None:
    """Require an explicit full commit; never overwrite any earlier public snapshot."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('export', 'receive'))
    parser.add_argument('--commit', required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--git-dir', type=Path)
    args = parser.parse_args()
    if re.fullmatch('[0-9a-f]{40}', args.commit) is None:
        raise ValueError('Owner-provided full commit is required')
    directory = args.directory.resolve()
    if args.mode == 'export':
        if directory.exists() or args.git_dir is None:
            raise ValueError('New export directory and explicit backing Git store required')
        archive = subprocess.run(['git', '--git-dir', str(args.git_dir), 'archive', '--format=tar', args.commit],
            capture_output=True, check=True, timeout=60).stdout
        files = public_files(archive)
        compressed = gzip.compress(archive, mtime=0)
        metadata = {'sourceCommit': args.commit, 'archiveBytes': len(archive), 'archiveSha256': digest(archive),
            'compressedArchiveBytes': len(compressed), 'compressedArchiveSha256': digest(compressed),
            'sourceFilesSha256': {name: digest(data) for name, data, _ in files}}
        directory.mkdir(parents=True, mode=0o700)
        (directory / 'core.tar.gz').write_bytes(compressed)
        (directory / 'snapshot.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
    else:
        metadata = json.loads((directory / 'snapshot.json').read_text())
        compressed = (directory / 'core.tar.gz').read_bytes()
        archive = gzip.decompress(compressed)
        files = public_files(archive)
        if (metadata['sourceCommit'] != args.commit or metadata['compressedArchiveSha256'] != digest(compressed)
                or metadata['archiveSha256'] != digest(archive) or metadata['archiveBytes'] != len(archive)
                or metadata['compressedArchiveBytes'] != len(compressed)
                or metadata['sourceFilesSha256'] != {name: digest(data) for name, data, _ in files}):
            raise ValueError('Public snapshot/transport binding differs')
        root = directory / 'core'
        root.mkdir(mode=0o700)
        for name, data, mode in files:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(mode)
        if any(digest((root / name).read_bytes()) != digest(data) for name, data, _ in files):
            raise ValueError('Received source bytes differ')
    print(json.dumps({'sourceCommit': args.commit, 'sourceFiles': len(files),
        'archiveSha256': metadata['compressedArchiveSha256'], 'snapshotSha256': digest((directory / 'snapshot.json').read_bytes())}))


if __name__ == '__main__':
    main()
