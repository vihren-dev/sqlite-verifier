"""Resource failures must happen before snapshots, toolchain installs or package copies."""

from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch
import sys
import os

from tools.check_resources import check_environment, check_resources, MIN_FREE_BYTES, MAX_ENVIRONMENT_BYTES


class ResourceTests(unittest.TestCase):
    """Use small fixtures and mocked capacity, never fill a disk to test the guard."""

    def test_package_preflight_precedes_external_work(self) -> None:
        """A direct archive invocation must stop before inspecting or copying runtimes."""
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'packaging'))
        import build_runtime
        with patch.object(build_runtime, 'check_resources', side_effect=ValueError('capacity')), \
             patch.object(build_runtime, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'capacity'):
                build_runtime.build()
            run.assert_not_called()

    def test_separate_temporary_filesystem(self) -> None:
        """Enough workspace capacity cannot hide a full temporary filesystem."""
        from tools.check_resources import existing_parent
        separate = MagicMock(spec=Path)
        separate.stat.return_value.st_dev = -1
        separate.__str__.return_value = '/separate/tmp'
        def destination(path: Path) -> Path:
            """Model a temporary volume independent of the real workspace."""
            return separate if path == Path('/separate/tmp') else existing_parent(path)
        def capacity(path: Path) -> SimpleNamespace:
            """Only the separate temporary destination lacks capacity."""
            return SimpleNamespace(free=0 if path is separate else MIN_FREE_BYTES)
        with patch('tools.check_resources.check_environment'), \
             patch('tools.check_resources.tempfile.gettempdir', return_value='/separate/tmp'), \
             patch('tools.check_resources.existing_parent', side_effect=destination), \
             patch('tools.check_resources.shutil.disk_usage', side_effect=capacity):
            with self.assertRaisesRegex(ValueError, '/separate/tmp: 0.00 GiB'):
                check_resources(Path.cwd())
        with patch('tools.check_resources.check_environment'), \
             patch.dict(os.environ, {'ELAN_HOME': '/separate/tmp'}), \
             patch('tools.check_resources.existing_parent', side_effect=destination), \
             patch('tools.check_resources.shutil.disk_usage', side_effect=capacity):
            with self.assertRaisesRegex(ValueError, '/separate/tmp: 0.00 GiB'):
                check_resources(Path.cwd())

    def test_environment_and_capacity_boundaries(self) -> None:
        """Accept small pins, reject oversized/symlinked inputs and low-space destinations."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            environment = root / 'nix'
            environment.mkdir()
            flake = environment / 'flake.nix'
            flake.write_text('{}')
            (environment / 'flake.lock').write_text('{}')
            self.assertEqual(check_environment(root), 4)
            with patch('tools.check_resources.shutil.disk_usage', return_value=SimpleNamespace(free=MIN_FREE_BYTES)):
                check_resources(root)
            with patch('tools.check_resources.shutil.disk_usage', return_value=SimpleNamespace(free=MIN_FREE_BYTES - 1)):
                with self.assertRaisesRegex(ValueError, '10 GiB'):
                    check_resources(root)
            with flake.open('wb') as output:
                output.truncate(MAX_ENVIRONMENT_BYTES + 1)
            with self.assertRaisesRegex(ValueError, 'exceed 1 MiB'):
                check_environment(root)
            flake.unlink()
            outside = root / 'outside.nix'
            outside.write_text('{}')
            flake.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'Unexpected environment input'):
                check_environment(root)
            flake.unlink()
            flake.write_text('{}')
            (environment / 'dist').mkdir()
            with self.assertRaisesRegex(ValueError, 'Unexpected environment input'):
                check_environment(root)


if __name__ == '__main__':
    unittest.main()
