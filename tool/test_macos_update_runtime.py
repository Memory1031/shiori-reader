"""Opt-in real Flutter/DMG upgrade on a disposable GitHub macOS runner."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

from release_macos import package
from release_receipt import file_record
from update_manifest import encoded, identity, key_from_private, openssl, sign_manifest


def run(*args, **options):
    return subprocess.run(list(map(str, args)), check=True, timeout=600, **options)


def wait_for(probe, description, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = probe()
        if value:
            return value
        time.sleep(.1)
    raise RuntimeError('Timed out: ' + description)


def main():
    if sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Run only on a disposable GitHub macOS runner; no local user data is used.')
    root = Path(__file__).resolve().parent.parent
    output = root / '.tooling/evidence/macos-update-check'
    output.mkdir(parents=True, exist_ok=True)
    pinned = json.loads((root / '.fvmrc').read_text())['flutter']
    actual = json.loads(subprocess.check_output(['flutter', '--version', '--machine']))
    assert actual['frameworkVersion'] == pinned
    configs = [root / p for p in ['assets/release/build-info.json',
        'macos/Flutter/ephemeral/Flutter-Generated.xcconfig',
        'macos/Flutter/ephemeral/flutter_export_environment.sh',
        'ios/Flutter/Generated.xcconfig', 'ios/Flutter/flutter_export_environment.sh']]
    original = {p: p.read_bytes() for p in configs if p.exists()}
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    with tempfile.TemporaryDirectory(prefix='shiori-real-dmg-') as temporary:
        stage = Path(temporary).resolve()
        secret_file = stage / 'test-key.pem'
        secret_file.write_bytes(openssl('genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:3072'))
        key = key_from_private(secret_file)
        releases = []
        try:
            for version, build in [('0.0.1', 21), ('0.0.2', 22)]:
                tag = 'v' + version
                release = identity(f'version: {version}+{build}', tag, commit)
                configs[0].write_bytes(encoded(dict(schemaVersion=1, identity=release, publicKey=key)))
                with (output / (tag + '-build.log')).open('w') as log:
                    run('flutter', 'build', 'macos', '--release', '--no-pub', '--target', 'lib/main.dart',
                        '--build-name=' + version, '--build-number=' + str(build),
                        cwd=root, stdout=log, stderr=subprocess.STDOUT)
                fixture = stage / tag; fixture.mkdir()
                (fixture / 'pubspec.yaml').write_text(f'version: {version}+{build}\n')
                app = fixture / 'Shiori.app'
                run('ditto', root / 'build/macos/Build/Products/Release/Shiori.app', app)
                package(fixture, app, fixture / 'assets', tag, commit, key)
                releases.append((release, fixture / 'assets' / f'shiori-reader-{tag}-macos-universal.dmg'))
        finally:
            configs[0].write_bytes(original[configs[0]])
            try:
                with (output / 'restore-normal-build.log').open('w') as log:
                    run('flutter', 'build', 'macos', '--release', '--no-pub', '--target', 'lib/main.dart',
                        cwd=root, stdout=log, stderr=subprocess.STDOUT)
            finally:
                for path, data in original.items():
                    path.write_bytes(data)
                assert all(p.read_bytes() == data for p, data in original.items())
        test_upgrade(stage, output, releases, secret_file.read_bytes(), key)


def test_upgrade(stage, output, releases, secret, key):
    # Cocoa lifecycle requests exercise normal application termination, without
    # UI automation or production-only failure injection switches.
    swift = stage / 'Lifecycle.swift'
    swift.write_text('''import AppKit
let action = CommandLine.arguments[1], value = CommandLine.arguments[2]
if action == "find" {
  for app in NSWorkspace.shared.runningApplications {
    if app.bundleURL?.resolvingSymlinksInPath().path == value && app.isFinishedLaunching {
      print(app.processIdentifier); exit(0)
    }
  }
  exit(1)
}
guard let app = NSRunningApplication(processIdentifier:Int32(value)!) else { exit(1) }
if action == "quit" { exit(app.terminate() ? 0 : 2) }
exit(app.isFinishedLaunching ? 0 : 1)
''')
    lifecycle = stage / 'lifecycle'
    run('xcrun', 'swiftc', swift, '-o', lifecycle)
    install = stage / 'Installed/Shiori.app'; install.parent.mkdir()
    mount = stage / 'first-volume'; mount.mkdir()
    try:
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', mount, releases[0][1])
        run('ditto', mount / 'Shiori.app', install)
    finally:
        if os.path.ismount(mount): run('hdiutil', 'detach', mount)
    workspace = Path(str(install) + '.update'); workspace.mkdir(mode=0o700)
    (workspace / 'owner.json').write_bytes(encoded(dict(format='ShioriMacUpdate/1', installation=str(install))))
    (workspace / 'package.zip').write_bytes(b'retired idle workspace fixture')
    helper = install / 'Contents/MacOS/shiori-updater'
    assert subprocess.check_output([str(helper), 'recover', str(install)]).strip() == b'idle'
    assert json.loads((workspace / 'owner.json').read_bytes())['format'] == 'ShioriMacUpdate/2'
    users = Path.home() / 'Library/Application Support/dev.shiori.reader/shiori/production/users'
    users.mkdir(parents=True, exist_ok=True)
    sentinel = users / 'update-preservation-fixture.txt'
    sentinel.write_text('self-authored user data fixture')
    expected_sentinel = hashlib.sha256(sentinel.read_bytes()).hexdigest()
    (users / 'update-preferences.json').write_bytes(encoded(dict(schema=1, channel='stable', automatic=False,
        lastAttempt=None, lastChecked=None, retryAt=None)))
    database = users / 'users.sqlite'

    def snapshot():
        with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as db:
            tables = [r[0] for r in db.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%'")]
            return {t: sorted(repr(r) for r in db.execute('select * from "' + t.replace('"', '""') + '"')) for t in tables}

    def find():
        result = subprocess.run([str(lifecycle), 'find', str(install)], capture_output=True, text=True)
        return int(result.stdout.strip()) if result.returncode == 0 else None

    old = None
    old_log = (output / 'old-application.log').open('w')
    try:
        old = subprocess.Popen([str(install / 'Contents/MacOS/Shiori')], stdout=old_log, stderr=subprocess.STDOUT)
        wait_for(lambda: find() == old.pid and database.exists(), 'original app and database ready')
        before = snapshot()
        release, dmg = releases[1]
        assets = [dict(platform=p, name=f'shiori-reader-{release["tag"]}-{suffix}', size=1,
            sha256='0'*64, minimumSystem='24' if p == 'android' else '10.0.17763', updaterProtocol=2)
            for p, suffix in [('android', 'android.apk'), ('windows-x64-portable', 'windows-x64.zip'),
                              ('windows-x64-setup', 'windows-x64-setup.exe')]]
        assets.append(dict(platform='macos-universal', **file_record(dmg), minimumSystem='12.0', updaterProtocol=2))
        raw = encoded(dict(schemaVersion=2, algorithm='rsa3072-pkcs1-sha256', keyId=key['keyId'], **release, assets=assets))
        manifest, signature = stage / 'manifest', stage / 'signature'
        manifest.write_bytes(raw); signature.write_bytes(sign_manifest(raw, secret, key))
        run(helper, 'prepare', install, dmg, manifest, signature)
        assert not (workspace / 'volume').exists()
        handoff = workspace / 'handoff'; shutil.copy2(helper, handoff)
        with (output / 'updater.log').open('w') as log:
            updater = subprocess.Popen([str(handoff), 'run', str(install), str(old.pid)], stdout=log, stderr=subprocess.STDOUT)
            try:
                def started():
                    path = workspace / 'started.json'
                    if not path.exists(): return False
                    state = json.loads(path.read_bytes())
                    return state.get('pid') == updater.pid and state.get('parent') == old.pid
                wait_for(started, 'native handoff')
                run(lifecycle, 'quit', old.pid)
                assert old.wait(timeout=30) == 0
                assert updater.wait(timeout=120) == 0
            finally:
                if updater.poll() is None: updater.kill(); updater.wait(timeout=10)
        new_pid = wait_for(find, 'updated app launched')
        assert new_pid != old.pid
        info = plistlib.loads((install / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleShortVersionString'] == release['version'] and str(info['CFBundleVersion']) == str(release['build'])
        run('codesign', '--verify', '--deep', '--strict', install)
        assert snapshot() == before
        assert hashlib.sha256(sentinel.read_bytes()).hexdigest() == expected_sentinel
        assert subprocess.check_output([str(helper), 'recover', str(install)]).strip() == b'installed'
        assert not (workspace / 'volume').exists() and not (workspace / 'previous.app').exists()
        (output / 'result.json').write_bytes(encoded(dict(fromBuild=releases[0][0]['build'], toBuild=release['build'],
            architecture=os.uname().machine, legacyWorkspaceMigrated=True, signedDmgUpgrade=True,
            applicationRelaunched=True, databaseRowsPreserved=True, userFilePreserved=True, mountCleaned=True)))
    finally:
        current = find()
        if current: run(lifecycle, 'quit', current)
        if old is not None and old.poll() is None: old.wait(timeout=30)
        old_log.close()


if __name__ == '__main__':
    main()
