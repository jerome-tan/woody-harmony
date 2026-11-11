import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_manifest', Path(__file__).resolve().parents[1] / 'scripts/release-manifest.py')
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)


class ReleaseManifestTest(unittest.TestCase):
    def test_complete_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('mac-arm64-portable.zip', 'mac-x64-portable.zip', 'win-x64-portable.zip', 'win-x64-setup.exe'):
                (root / ('Woody-1.2.3-qt-' + name)).write_bytes(b'package')
            (root / 'SHA256SUMS.txt').write_text('checksum')
            result = manifest.build_manifest(root, '1.2.3', 'Release notes')
            self.assertEqual(result['tag_name'], 'v1.2.3')
            self.assertEqual(len(result['assets']), 5)
            self.assertTrue(all('/releases/download/v1.2.3/' in a['browser_download_url'] for a in result['assets']))
            self.assertEqual(result['body'], 'Release notes')

    def test_incomplete_release_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                manifest.build_manifest(Path(directory), '1.2.3')

    def test_prerelease_is_rejected(self):
        with self.assertRaises(ValueError):
            manifest.build_manifest(Path('.'), '1.2.3-rc1')
