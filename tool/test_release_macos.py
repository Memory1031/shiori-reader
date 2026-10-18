import json
from contextlib import contextmanager
import os
from pathlib import Path
import plistlib
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile

from update_manifest import encoded, identity, key_from_private, openssl, sha, sign_manifest
from release_macos import BUNDLE_IDENTITY, verify_bundle, sign_locally
from release_receipt import file_record
from release_android import ReleaseCheckError
from build_macos_helper import build


class MacOSUpdateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.keys = tempfile.TemporaryDirectory(prefix='shiori-mac-test-key-')
        cls.addClassCleanup(cls.keys.cleanup)
        key = Path(cls.keys.name) / 'key.pem'
        key.write_bytes(openssl('genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:3072'))
        cls.secret, cls.key = key.read_bytes(), key_from_private(key)
        cls.old = identity('version: 1.3.1+19', 'v1.3.1', 'a' * 40)
        cls.new = identity('version: 1.3.2+20', 'v1.3.2', 'b' * 40)
        if sys.platform == 'darwin':
            root = Path(cls.keys.name)
            (root / 'assets/release').mkdir(parents=True)
            (root / 'assets/release/build-info.json').write_bytes(encoded(dict(schemaVersion=1, identity=cls.old, publicKey=cls.key)))
            (root / 'macos').mkdir()
            (root / 'macos/Updater').symlink_to(Path(__file__).resolve().parent.parent / 'macos/Updater')
            cls.helper = root / 'shiori-updater'
            build(root, cls.helper, ['arm64', 'x86_64'], testing=True)
            probe = root / 'LeaseProbe.swift'
            probe.write_text('''import Foundation
import Darwin
@main struct Probe {
  static func main() {
    do {
      let fd = try acquireInstallationLease(URL(fileURLWithPath:CommandLine.arguments[1]))
      print("leased"); fflush(stdout)
      _ = readLine(); close(fd)
    } catch let error as POSIXError where error.code == .EWOULDBLOCK { exit(73) }
    catch { exit(74) }
  }
}
''')
            cls.launcher = root / 'launch-probe'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / 'swift-cache'), str(probe), str(Path(__file__).resolve().parent.parent / 'macos/Runner/InstallationLease.swift'), '-o', str(cls.launcher)], check=True)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='shiori-macos-update-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / 'pubspec.yaml').write_text('version: 1.3.2+20\n')
        self.assets = self.root / 'assets'; self.assets.mkdir()
        self.package = self.assets / 'shiori-reader-v1.3.2-macos-universal.dmg'
        self.install = self.root / 'Shiori.app'
        self.workspace = Path(str(self.install) + '.update')
        self.make_bundle(self.install, self.old)
        self.bundle = self.root / 'payload/Shiori.app'
        self.make_bundle(self.bundle, self.new)
        self.archive()

    def make_bundle(self, path, release):
        (path / 'Contents/MacOS').mkdir(parents=True)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='dev.shiori.reader', CFBundleShortVersionString=release['version'], CFBundleVersion=str(release['build']))))
        for name in ['Shiori', 'shiori-updater']:
            p = path / 'Contents/MacOS' / name
            p.write_text('#!/bin/sh\nexit 0\n'); p.chmod(0o755)
        info = path / BUNDLE_IDENTITY.removeprefix('Shiori.app/').replace('/App.framework/Resources/', '/App.framework/Versions/A/Resources/')
        info.parent.mkdir(parents=True)
        info.write_bytes(encoded(dict(schemaVersion=1, identity=release, publicKey=self.key)))
        (path / 'Contents/Frameworks/App.framework/Resources').symlink_to(Path('Versions/A/Resources'), target_is_directory=True)
        (path / 'Contents/Frameworks/current').symlink_to('App.framework', target_is_directory=True)

    def archive(self):
        self.package.unlink(missing_ok=True)
        if sys.platform == 'darwin':
            subprocess.run(['hdiutil', 'create', '-volname', 'Shiori fixture', '-srcfolder',
                            str(self.bundle.parent), '-format', 'UDZO', str(self.package)], check=True, capture_output=True)
        else:
            self.package.write_bytes(b'synthetic DMG; never mounted outside macOS')

    def signed(self):
        assets = [dict(platform=platform, name=f'shiori-reader-v1.3.2-{suffix}', size=1, sha256='0'*64,
                       minimumSystem='24' if platform == 'android' else '10.0.17763', updaterProtocol=2)
                  for platform, suffix in [('android', 'android.apk'), ('windows-x64-portable', 'windows-x64.zip'), ('windows-x64-setup', 'windows-x64-setup.exe')]]
        assets.append(dict(platform='macos-universal', **file_record(self.package), minimumSystem='12.0', updaterProtocol=2))
        raw = encoded(dict(schemaVersion=2, algorithm='rsa3072-pkcs1-sha256', keyId=self.key['keyId'], **self.new, assets=assets))
        manifest, signature = self.root / 'manifest.json', self.root / 'manifest.sig'
        manifest.write_bytes(raw); signature.write_bytes(sign_manifest(raw, self.secret, self.key))
        return manifest, signature

    def call(self, mode, *args, env=None, success=True):
        p = subprocess.run([str(self.helper), mode, str(self.install), *map(str,args)], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(p.returncode == 0, success, p.stdout + p.stderr)
        return p

    def prepare(self):
        manifest, signature = self.signed()
        self.call('prepare', self.package, manifest, signature)

    def run_update(self, env=None, success=True):
        parent = subprocess.Popen(['/bin/sleep', '15'])
        try:
            process = subprocess.Popen([str(self.helper), 'run', str(self.install), str(parent.pid)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
            deadline = time.monotonic() + 10
            while not (self.workspace / 'started.json').exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue((self.workspace / 'started.json').exists())
            parent.terminate(); parent.wait(timeout=5)
            stdout, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode == 0, success, stdout + stderr)
            return process.returncode
        finally:
            if parent.poll() is None: parent.kill(); parent.wait()

    @contextmanager
    def paused_update(self, stage):
        self.prepare()
        parent = subprocess.Popen(['/bin/sleep', '15'])
        gate = self.root / 'commit-gate'
        process = subprocess.Popen([str(self.helper), 'run', str(self.install), str(parent.pid)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={**os.environ, 'SHIORI_UPDATE_PAUSE':stage, 'SHIORI_UPDATE_GATE':str(gate)})
        def wait_for(path):
            deadline = time.monotonic() + 10
            while not path.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(path.exists(), f'Updater did not reach {stage}')
        try:
            wait_for(self.workspace / 'started.json')
            parent.terminate(); parent.wait(timeout=5)
            wait_for(Path(str(gate) + '.ready'))
            yield process, Path(str(gate) + '.release')
        finally:
            if parent.poll() is None: parent.kill(); parent.wait()
            if process.poll() is None: process.kill()
            process.communicate(timeout=5)

    def test_unified_manifest_selects_dmg_and_preserves_exact_signature(self):
        manifest, signature = self.signed()
        value = json.loads(manifest.read_text())
        self.assertEqual(value['schemaVersion'], 2)
        self.assertEqual(len(value['assets']), 4)
        self.assertEqual(value['assets'][-1]['name'], self.package.name)
        self.assertEqual(value['assets'][-1]['minimumSystem'], '12.0')
        self.assertEqual(signature.stat().st_size, 384)

    def test_reject_escaping_bundle_links_and_identity(self):
        link = self.bundle / 'Contents/escape'
        link.symlink_to('../../outside')
        with self.assertRaises(ReleaseCheckError):
            verify_bundle(self.bundle, self.new, self.key)
        link.unlink()
        identity_path = self.bundle / BUNDLE_IDENTITY.removeprefix('Shiori.app/').replace('/App.framework/Resources/', '/App.framework/Versions/A/Resources/')
        identity_path.write_bytes(encoded(dict(schemaVersion=1, development=True)))
        with self.assertRaises(ReleaseCheckError):
            verify_bundle(self.bundle, self.new, self.key)

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS signing')
    def test_ad_hoc_signs_nested_helper_and_complete_bundle(self):
        shutil.rmtree(self.install / 'Contents/Frameworks')
        for name in ['Shiori', 'shiori-updater']:
            shutil.copy2(self.helper, self.install / 'Contents/MacOS' / name)
        info = self.install / 'Contents/Info.plist'
        info.write_bytes(plistlib.dumps(dict(CFBundleIdentifier='dev.shiori.reader', CFBundleExecutable='Shiori', CFBundlePackageType='APPL')))
        sign_locally(self.install)

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_refuses_bad_signature_and_other_running_instance(self):
        manifest, signature = self.signed()
        signature.write_bytes(b'0' * 384)
        result = self.call('prepare', self.package, manifest, signature, success=False)
        self.assertIn('verification', result.stderr)
        self.prepare()
        result = self.call('run', '999999', env={**os.environ, 'SHIORI_UPDATE_OTHER_INSTANCE':'1'}, success=False)
        self.assertIn('instances', result.stderr)
        self.assertFalse((self.workspace / 'transaction.json').exists())
        self.run_update(env={**os.environ, 'SHIORI_UPDATE_LATE_INSTANCE':'1'}, success=False)
        self.assertFalse((self.workspace / 'transaction.json').exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_reader_started_after_parent_exit_prevents_replacement(self):
        with self.paused_update('before-commit') as (update, release):
            reader = subprocess.Popen([str(self.launcher), str(self.install)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(reader.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=5))
                self.assertEqual(reader.stdout.readline().strip(), 'leased')
                release.touch()
                stdout, stderr = update.communicate(timeout=10)
                self.assertNotEqual(update.returncode, 0, stdout + stderr)
                self.assertIn('instances', stderr)
                self.assertEqual(plistlib.loads((self.install / 'Contents/Info.plist').read_bytes())['CFBundleVersion'], '19')
                self.assertFalse((self.workspace / 'transaction.json').exists())
                self.assertIsNone(reader.poll())
            finally:
                reader.communicate(input='\n', timeout=5)

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_commit_blocks_new_startup_until_bundle_exchange_finishes(self):
        with self.paused_update('committing') as (update, release):
            reader = subprocess.run([str(self.launcher), str(self.install)], input='', capture_output=True, text=True, timeout=5)
            self.assertEqual(reader.returncode, 73)
            release.touch()
            stdout, stderr = update.communicate(timeout=10)
            self.assertEqual(update.returncode, 0, stdout + stderr)
            self.assertEqual(plistlib.loads((self.install / 'Contents/Info.plist').read_bytes())['CFBundleVersion'], '20')
        reader = subprocess.run([str(self.launcher), str(self.install)], input='', capture_output=True, text=True, timeout=5)
        self.assertEqual(reader.returncode, 0, reader.stderr)

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_upgrade_reextracts_staging_and_preserves_user_data(self):
        data = self.root / 'reading.sqlite'; data.write_text('user-owned data')
        self.prepare()
        (self.workspace / 'payload/Shiori.app/Contents/MacOS/Shiori').write_text('tampered staging')
        self.run_update()
        self.assertEqual(self.call('recover').stdout.strip(), 'installed')
        self.assertEqual(data.read_text(), 'user-owned data')
        self.assertEqual((self.install / 'Contents/MacOS/Shiori').read_text(), '#!/bin/sh\nexit 0\n')
        self.assertTrue((self.install / 'Contents/Frameworks/current').is_symlink())
        self.assertFalse((self.workspace / 'previous.app').exists())
        self.assertEqual(self.call('recover').stdout.strip(), 'idle')

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_rejects_tampering_before_any_replacement(self):
        self.prepare()
        with (self.workspace / 'package.dmg').open('ab') as f: f.write(b'x')
        result = self.call('run', '999999', success=False)
        self.assertIn('verification', result.stderr)
        self.assertFalse((self.workspace / 'previous.app').exists())
        self.assertTrue(self.install.exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_launch_failure_restores_original_bundle(self):
        self.prepare()
        self.run_update(env={**os.environ, 'SHIORI_UPDATE_LAUNCH_FAIL':'1'}, success=False)
        info = plistlib.loads((self.install / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleVersion'], '19')

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_interrupted_replacement_recovers_at_each_commit_boundary(self):
        for stage, expected in [('mounted','19'), ('planned','19'), ('swapped','20'), ('backed-up','20'), ('replaced','20')]:
            with self.subTest(stage=stage):
                if self.workspace.exists(): shutil.rmtree(self.workspace)
                if self.install.exists(): shutil.rmtree(self.install)
                self.make_bundle(self.install, self.old)
                self.prepare()
                self.run_update(env={**os.environ,'SHIORI_UPDATE_STOP':stage},success=False)
                self.call('recover')
                self.assertFalse((self.workspace / 'volume').exists())
                info = plistlib.loads((self.install / 'Contents/Info.plist').read_bytes())
                self.assertEqual(info['CFBundleVersion'], expected)

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS updater')
    def test_refuses_foreign_workspace(self):
        self.workspace.mkdir(); note = self.workspace / 'personal.txt'; note.write_text('keep')
        self.assertIn('workspaceConflict', self.call('recover',success=False).stderr)
        self.assertEqual(note.read_text(), 'keep')


if __name__ == '__main__': unittest.main()
