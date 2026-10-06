"""Bind full native replay to explicit ordinary-file storage and retained execution conditions."""

import hashlib
import shutil
import sys
from pathlib import Path
from time import monotonic

from conformance.case_format import Json
from conformance.corpus import native_replay
from conformance.native_connection import library_path
from conformance.native_library import DEFAULT_ENGINE_VERSION, library_binary
from conformance.native_storage import serialized
from conformance.progress import RUNTIME_FILES
from tools.check_resources import check_resources

ROOT = Path(__file__).resolve().parents[1]


def bindings(corpus: Path, records: list[dict[str, Json]], runtime: Path | None) -> dict[str, Json]:
    """Hash actual code, corpus, runtime and selected native library bytes before and after replay."""
    versions = {record['profile']['engineVersion'] if record['nativeVersion'] == 4 else DEFAULT_ENGINE_VERSION
                for record in records}
    libraries = [library_path(library_binary(version)) for version in sorted(versions)]
    sources = [*sorted((ROOT / 'conformance').glob('*.py')),
               *sorted((ROOT / 'migration_check').glob('*.py')),
               ROOT / 'tools/check_resources.py', ROOT / 'nix/sqlite.nix', ROOT / 'nix/flake.lock']
    return {'sourcesSha256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in sources},
            'corpusFilesSha256': {str(path.relative_to(corpus)): hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in sorted(corpus.rglob('*')) if path.is_file()},
            'recordedInputsSha256': hashlib.sha256(serialized(records)).hexdigest(),
            'runtimeSha256': {name: hashlib.sha256((runtime / name).read_bytes()).hexdigest()
                              for name in RUNTIME_FILES} if runtime is not None else {},
            'nativeLibrariesSha256': {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in libraries}}


def storage_resources(directory: Path) -> dict[str, Json]:
    """Expose the capacity and actual device of the selected fixture filesystem."""
    usage = shutil.disk_usage(directory)
    return {'path': str(directory), 'device': directory.stat().st_dev,
            'totalBytes': usage.total, 'usedBytes': usage.used, 'freeBytes': usage.free}


def report(corpus: Path, records: list[dict[str, Json]], runtime: Path | None,
           temporary_root: Path) -> dict[str, Json]:
    """Pass only after exact frozen comparisons and unchanged bindings on the declared storage."""
    temporary_root = temporary_root.resolve()
    check_resources(ROOT, temporary_root=temporary_root)
    before = bindings(corpus, records, runtime)
    resources = storage_resources(temporary_root)
    paths: list[Path] = []
    started = monotonic()
    native_replay(records, temporary_root=temporary_root, fixture_paths=paths)
    seconds = monotonic() - started
    after = bindings(corpus, records, runtime)
    if before != after:
        raise ValueError('Full native replay inputs changed; restore the source, corpus and runtime before retrying')
    if len(paths) != len(records) or any(path.parent.parent != temporary_root for path in paths):
        raise ValueError('Native fixtures differ from the selected temporary root; check the native recorder')
    return {'nativeReplay': {'passed': True, 'seconds': seconds,
                'command': list(sys.orig_argv),
                'bindingsBefore': before, 'bindingsAfter': after, 'bindingsUnchanged': True,
                'temporaryStorage': {'databaseKind': 'ordinary-file', 'selectedRoot': str(temporary_root),
                    'resourcesBefore': resources, 'resourcesAfter': storage_resources(temporary_root),
                    'fixtureCount': len(paths), 'fixturePaths': [str(path) for path in paths],
                    'allFixturesBeneathSelectedRoot': True}}}
