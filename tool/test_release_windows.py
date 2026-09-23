import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

from release_windows import (BUILD_INFO, CRT, RUNTIME, NATIVE_PACKAGES, NATIVE_NOTICES,
                             PROGRAM_FILES, ReleaseCheckError, package)


class WindowsReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'Release'
        self.crt = self.root / 'crt'
        self.output = self.root / 'output'
        (self.root / 'pubspec.yaml').write_text('version: 1.2.0+9\n')
        (self.root / 'LICENSE').write_text('Synthetic license')
        for directory, paths in [(self.bundle, RUNTIME), (self.crt, CRT),
                                 (self.root / NATIVE_PACKAGES, NATIVE_NOTICES),
                                 (self.root, ['tool/licenses/nlohmann-json-3.11.2-LICENSE.MIT'])]:
            for relative in paths:
                path = directory / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'synthetic')
        pe = bytearray(70)
        pe[:2] = b'MZ'
        struct.pack_into('<I', pe, 60, 64)
        pe[64:] = b'PE\0\0\x64\x86'
        (self.bundle / 'shiori.exe').write_bytes(pe)
        (self.bundle / BUILD_INFO).parent.mkdir(parents=True, exist_ok=True)
        (self.bundle / BUILD_INFO).write_text('{"schemaVersion":1,"development":true}\n')
        self.metadata = dict(ProductName='Shiori', OriginalFilename='shiori.exe',
                             ProductVersion='1.2.0+9', FileMajorPart=1, FileMinorPart=2,
                             FileBuildPart=0, FilePrivatePart=9, IsDebug=False)

    def package(self, **kwargs):
        return package(self.root, self.bundle, self.crt, self.output,
                       kwargs.get('tag', 'v1.2.0'), 'a' * 40, lambda _: self.metadata)

    def test_zip_layout_hash_and_platform_metadata(self):
        (self.bundle / 'shiori.pdb').write_bytes(b'debug symbols')
        (self.bundle / 'native_assets.json').write_text('build-machine-path')
        archive = self.package()
        with zipfile.ZipFile(archive) as zipped:
            self.assertTrue(set(RUNTIME + CRT).issubset(zipped.namelist()))
            self.assertNotIn('shiori.pdb', zipped.namelist())
            self.assertNotIn('native_assets.json', zipped.namelist())
            self.assertTrue(all('licenses/' + notice in zipped.namelist() for notice in NATIVE_NOTICES))
            self.assertTrue(all(not name.startswith('Release/') for name in zipped.namelist()))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.assertEqual((self.output / 'SHA256SUMS-windows-x64.txt').read_text(),
                         f'{digest}  {archive.name}\n')
        metadata = json.loads((self.output / 'release-info-windows-x64.json').read_text())
        self.assertEqual(metadata['sha256'], digest)
        self.assertFalse(metadata['signed'])
        self.assertFalse((self.output / 'SHA256SUMS.txt').exists())

    def test_program_file_list_names_every_entry_including_itself(self):
        with zipfile.ZipFile(self.package()) as zipped:
            listing = zipped.read(PROGRAM_FILES).decode('utf-8')
            self.assertEqual(listing, ''.join(name + '\n' for name in sorted(zipped.namelist())))
            self.assertIn('shiori-updater.exe\n', listing)

    def test_updater_must_embed_bundled_update_key(self):
        modulus = '8' + 'a' * 767
        (self.bundle / BUILD_INFO).write_text(json.dumps({'publicKey': {'modulus': modulus}}))
        with self.assertRaisesRegex(ReleaseCheckError, 'updater'):
            self.package()
        (self.bundle / 'shiori-updater.exe').write_bytes(b'MZ...' + modulus.encode() + b'...')
        self.package()
        (self.bundle / 'shiori-updater.exe').unlink()
        with self.assertRaisesRegex(ReleaseCheckError, 'shiori-updater.exe'):
            self.package()

    def test_missing_dependency_and_stale_or_debug_executable_rejected(self):
        for key, value in [('FilePrivatePart', 8), ('ProductVersion', '1.1.0+9'),
                           ('IsDebug', True), ('ProductName', 'Other')]:
            with self.subTest(key=key):
                original = self.metadata[key]
                self.metadata[key] = value
                with self.assertRaises(ReleaseCheckError):
                    self.package()
                self.metadata[key] = original
        (self.bundle / 'sqlite3.dll').unlink()
        with self.assertRaises(ReleaseCheckError):
            self.package()

    def test_beta_archive_preserves_numeric_executable_version(self):
        archive = self.package(tag='v1.2.0-beta.1')
        self.assertEqual(archive.name, 'shiori-reader-v1.2.0-beta.1-windows-x64.zip')
        metadata = json.loads((self.output / 'release-info-windows-x64.json').read_text())
        self.assertEqual(metadata['tag'], 'v1.2.0-beta.1')
        self.assertEqual(metadata['versionName'], '1.2.0')
        self.assertEqual(str(metadata['versionCode']), '9')
        self.assertIn(archive.name, (self.output / 'SHA256SUMS-windows-x64.txt').read_text())
        with self.assertRaises(ReleaseCheckError):
            self.package(tag='v1.2.1-beta.1')

    def test_tag_and_architecture_rejected(self):
        with self.assertRaises(ReleaseCheckError):
            self.package(tag='v1.3.0')
        path = self.bundle / 'shiori.exe'
        data = bytearray(path.read_bytes())
        data[-2:] = b'\x4c\x01'
        path.write_bytes(data)
        with self.assertRaisesRegex(ReleaseCheckError, 'x64'):
            self.package()

    def test_missing_crt_or_notice_rejected(self):
        for path in [self.crt / CRT[0], self.root / NATIVE_PACKAGES / NATIVE_NOTICES[0]]:
            original = path.read_bytes()
            path.unlink()
            with self.assertRaisesRegex(ReleaseCheckError, 'Missing or empty'):
                self.package()
            path.write_bytes(original)


if __name__ == '__main__':
    unittest.main()
