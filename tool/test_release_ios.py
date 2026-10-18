import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from release_android import ReleaseCheckError
from release_ios import PREFIX, MACH_MAGIC, macho, package as package_release, verify_archive, verify_assets
from update_manifest import encoded, identity


def package(*args):
    # Windows has no POSIX executable bits. Encode synthetic Mach-O fixture
    # permissions explicitly; production validation and packaging stay strict.
    original = zipfile.ZipInfo.from_file
    def entry(filename, *values, **options):
        info = original(filename, *values, **options)
        if os.name == 'nt' and Path(filename).is_file():
            with open(filename, 'rb') as source:
                if source.read(4) in MACH_MAGIC:
                    info.external_attr = (stat.S_IFREG | 0o755) << 16
        return info
    with patch.object(zipfile.ZipInfo, 'from_file', side_effect=entry):
        return package_release(*args)



def device_code(platform=2, cpu=0x100000c, signed=False, encrypted=False, libraries=()):
    commands = [struct.pack('<6I', 0x32, 24, platform, 15 << 16, 26 << 16, 0)]
    if signed:
        commands.append(struct.pack('<4I', 0x1d, 16, 0, 0))
    if encrypted:
        commands.append(struct.pack('<6I', 0x2c, 24, 0, 0, 1, 0))
    for library in libraries:
        text = library.encode() + b'\0'
        size = (24 + len(text) + 7) & ~7
        commands.append(struct.pack('<6I', 0xc, size, 24, 0, 0, 0) + text.ljust(size - 24, b'\0'))
    load = b''.join(commands)
    return struct.pack('<8I', 0xfeedfacf, cpu, 0, 2, len(commands), len(load), 0, 0) + load


def fixture_app(root, expected):
    app = root / 'Runner.app'
    for folder, identifier, executable in [
        ('', 'dev.shiori.reader', 'Runner'),
        ('PlugIns/ShareExtension.appex', 'dev.shiori.reader.ShareExtension', 'ShareExtension'),
        ('Frameworks/App.framework', 'io.flutter.flutter.app', 'App'),
        ('Frameworks/Flutter.framework', 'io.flutter.flutter', 'Flutter'),
    ]:
        bundle = app / folder
        bundle.mkdir(parents=True)
        info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=executable,
                    CFBundleShortVersionString=expected['version'], CFBundleVersion=str(expected['build']),
                    MinimumOSVersion='15.0', CFBundleSupportedPlatforms=['iPhoneOS'])
        (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
        binary = bundle / executable
        binary.write_bytes(device_code())
        binary.chmod(0o755)
    assets = app / 'Frameworks/App.framework/flutter_assets'
    assets.mkdir()
    for resource in ['AssetManifest.bin', 'FontManifest.json', 'NOTICES.Z']:
        (assets / resource).write_bytes(b'synthetic fixture')
    return app


class IOSReleaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='shiori-ios-release-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.assets = self.root / 'assets'
        (self.root / 'pubspec.yaml').write_text('version: 1.2.1+11\n')
        self.tag, self.commit = 'v1.2.1-beta.1', 'a' * 40
        self.expected = identity('version: 1.2.1+11', self.tag, self.commit)
        self.app = fixture_app(self.root, self.expected)
        self.archive = self.assets / f'shiori-reader-{self.tag}-ios-arm64-unsigned.ipa'

    def package(self):
        package(self.root, self.app, self.assets, self.tag, self.commit)

    def rewrite(self, edit):
        with zipfile.ZipFile(self.archive) as source:
            entries = [(i, source.read(i)) for i in source.infolist()]
        with zipfile.ZipFile(self.archive, 'w') as target:
            for entry, raw in entries:
                value = edit(entry.filename, raw)
                if value is not None:
                    target.writestr(entry, value)

    def test_complete_package_metadata_and_device_architecture(self):
        self.package()
        self.assertEqual(verify_assets(self.root, self.assets, self.tag, self.commit),
                         {self.archive.name})
        with zipfile.ZipFile(self.archive) as archive:
            self.assertIn(PREFIX + 'PlugIns/ShareExtension.appex/ShareExtension', archive.namelist())
            self.assertIn(PREFIX + 'Frameworks/Flutter.framework/Flutter', archive.namelist())
        # The release identity is metadata only: this channel does not create an updater manifest.
        self.assertEqual(set(p.name for p in self.assets.iterdir()), {self.archive.name, 'receipts'})

    def test_device_only_unencrypted_unsigned_code(self):
        for options in [dict(platform=7), dict(platform=1), dict(cpu=0x1000007),
                        dict(signed=True), dict(encrypted=True)]:
            with self.subTest(options=options), self.assertRaises(ReleaseCheckError):
                macho(device_code(**options))
        for bad in [b'', b'not a macho', device_code()[:-1]]:
            with self.assertRaises(ReleaseCheckError):
                macho(bad)
        raw = device_code()
        fat = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 28, len(raw), 0) + raw
        macho(fat)
        with self.assertRaises(ReleaseCheckError):
            macho(fat[:8] + struct.pack('>I', 0x1000007) + fat[12:])
        self.package()
        self.rewrite(lambda name, raw: device_code(platform=7)
                     if name == PREFIX + 'Frameworks/Flutter.framework/Flutter' else raw)
        with self.assertRaises(ReleaseCheckError):
            verify_archive(self.archive, self.expected)

    def test_both_bundle_identities_and_versions_checked(self):
        self.package()
        original = self.archive.read_bytes()
        for folder in ['', 'PlugIns/ShareExtension.appex/']:
            for field, value in [('CFBundleIdentifier', 'other.app'), ('CFBundleVersion', '12'),
                                 ('CFBundleShortVersionString', '1.2.2'), ('CFBundleSupportedPlatforms', ['iPhoneSimulator'])]:
                self.archive.write_bytes(original)
                def edit(name, raw):
                    if name == PREFIX + folder + 'Info.plist':
                        info = plistlib.loads(raw)
                        info[field] = value
                        return plistlib.dumps(info)
                    return raw
                self.rewrite(edit)
                with self.subTest(folder=folder, field=field), self.assertRaises(ReleaseCheckError):
                    verify_archive(self.archive, self.expected)

    def test_missing_resources_framework_or_extension_rejected(self):
        self.package()
        original = self.archive.read_bytes()
        for name in ['Runner', 'PlugIns/ShareExtension.appex/ShareExtension', 'Frameworks/Flutter.framework/Flutter',
                     'Frameworks/App.framework/App', 'Frameworks/App.framework/Info.plist',
                     'Frameworks/App.framework/flutter_assets/AssetManifest.bin']:
            self.archive.write_bytes(original)
            self.rewrite(lambda path, raw: None if path == PREFIX + name else raw)
            with self.subTest(name=name), self.assertRaises((ReleaseCheckError, KeyError)):
                verify_archive(self.archive, self.expected)

    def test_dependencies_signatures_profiles_and_unsafe_paths_rejected(self):
        self.package()
        original = self.archive.read_bytes()
        self.rewrite(lambda path, raw: device_code(libraries=['@rpath/Missing.framework/Missing'])
                     if path == PREFIX + 'Runner' else raw)
        with self.assertRaises(ReleaseCheckError):
            verify_archive(self.archive, self.expected)
        for name in ['../escape', PREFIX + '../outside', PREFIX + '_CodeSignature/CodeResources',
                     PREFIX + 'embedded.mobileprovision', PREFIX + 'secret.p12', PREFIX + 'secret.p8',
                     PREFIX + 'Runner.dSYM/info', PREFIX + 'runner']:
            self.archive.write_bytes(original)
            with zipfile.ZipFile(self.archive, 'a') as archive:
                archive.writestr(name, b'forbidden')
            with self.subTest(name=name), self.assertRaises(ReleaseCheckError):
                verify_archive(self.archive, self.expected)
        self.archive.write_bytes(original)
        with zipfile.ZipFile(self.archive, 'a') as archive:
            entry = zipfile.ZipInfo(PREFIX + 'link')
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(entry, '../outside')
        with self.assertRaises(ReleaseCheckError):
            verify_archive(self.archive, self.expected)

    def test_receipt_identity_and_package_hash_are_bound(self):
        self.package()
        receipt = self.assets / 'receipts/ios-arm64.json'
        original = receipt.read_bytes()
        value = json.loads(original)
        for identity in [{**self.expected, 'build': 12}, {**self.expected, 'commit': 'b'*40}]:
            receipt.write_bytes(encoded({**value, 'identity': identity}))
            with self.assertRaises(ReleaseCheckError):
                verify_assets(self.root, self.assets, self.tag, self.commit)
        receipt.write_bytes(original)
        self.archive.write_bytes(self.archive.read_bytes() + b'tampered')
        with self.assertRaises(ReleaseCheckError):
            verify_assets(self.root, self.assets, self.tag, self.commit)

    def test_stale_profiles_removed_only_from_disposable_copy(self):
        for bundle in [self.app, self.app / 'PlugIns/ShareExtension.appex']:
            (bundle / 'embedded.mobileprovision').write_bytes(b'stale fixture profile')
        self.package()
        self.assertTrue((self.app / 'embedded.mobileprovision').exists())
        verify_archive(self.archive, self.expected)


if __name__ == '__main__':
    unittest.main()
