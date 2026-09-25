"""The Linux shell output RPATH is reusable only while it has no linker inputs."""

import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'parser'))
import build_cache
from tests import parser_build_test


class ShellRpathTests(unittest.TestCase):
    """Retain mutable search-path rejection while admitting the observed mkShell default."""

    def test_absent_output_rpath_only(self) -> None:
        """Directory creation, symlinks and other search kinds cannot gain cache admission."""
        with TemporaryDirectory() as directory:
            output = Path(directory) / 'out'
            library = output / 'lib'
            environment = {'out': str(output), 'NIX_LDFLAGS': f'-rpath {library}'}
            self.assertTrue(build_cache.stable_environment(environment))
            for flags in (f'-L{library}', f'-rpath-link {library}',
                          f'-rpath {output}/other', '-rpath', '-I',
                          f'-L -rpath {library}', f'-isystem -rpath {library}'):
                self.assertFalse(build_cache.stable_environment({**environment, 'NIX_LDFLAGS': flags}))
            self.assertFalse(build_cache.stable_environment({**environment, 'NIX_CFLAGS_COMPILE': f'-I{library}'}))
            for suffix in ('colon:other', '$ORIGIN'):
                unusual = output / suffix
                self.assertFalse(build_cache.stable_environment(
                    {'out': str(unusual), 'NIX_LDFLAGS': f'-rpath {unusual}/lib'}))
            library.mkdir(parents=True)
            self.assertFalse(build_cache.stable_environment(environment))
            library.rmdir()
            library.symlink_to(output / 'missing')
            self.assertFalse(build_cache.stable_environment(environment))

    def test_rpath_appearing_during_build_cannot_publish_stamp(self) -> None:
        """A successful tool cannot race a cacheable environment into a different input policy."""
        fixture = parser_build_test.IncrementalBuildTests()
        fixture.setUp()
        try:
            original = build_cache.identity
            calls = 0
            def changing(root: Path, upstream: Path, version: str, executable: str) -> tuple[str, str, bool]:
                """Model a directory becoming present after initial identity sampling."""
                nonlocal calls
                calls += 1
                cc, stamp, reusable = original(root, upstream, version, executable)
                return cc, stamp, reusable if calls == 1 else False
            with patch.object(sys.modules['build'], 'identity', side_effect=changing):
                with self.assertRaisesRegex(RuntimeError, 'inputs changed'):
                    fixture.build()
            self.assertFalse((fixture.root / 'build/parser/build-state.json').exists())
        finally:
            fixture.doCleanups()


if __name__ == '__main__':
    unittest.main()
