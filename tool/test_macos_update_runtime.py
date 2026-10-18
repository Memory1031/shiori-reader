"""Opt-in real Flutter/DMG upgrade on a disposable GitHub macOS runner."""
import hashlib
import ctypes
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
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
                print('Building and packaging test application ' + version, flush=True)
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
if action == "inspect" {
  for app in NSWorkspace.shared.runningApplications {
    print(app.processIdentifier, app.bundleURL?.path ?? "nil", app.executableURL?.path ?? "nil")
  }
  exit(0)
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

    proc_pidpath = ctypes.CDLL('/usr/lib/libproc.dylib').proc_pidpath
    proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    proc_pidpath.restype = ctypes.c_int

    def find():
        candidates = subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'Shiori'],
            capture_output=True, text=True)
        matches = []
        for candidate in candidates.stdout.split():
            pid = int(candidate)
            buffer = ctypes.create_string_buffer(4096)
            if proc_pidpath(pid, buffer, len(buffer)) > 0:
                if Path(os.fsdecode(buffer.value)).resolve() == (install / 'Contents/MacOS/Shiori').resolve():
                    matches.append(pid)
        assert len(matches) <= 1, 'Multiple processes use the disposable test bundle'
        return matches[0] if matches else None

    def database_ready(pid):
        if not database.exists(): return False
        try:
            with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as db:
                if db.execute('pragma user_version').fetchone()[0] != 9: return False
            opened = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(pid), '-Fn', str(database)],
                capture_output=True, text=True)
            return opened.returncode == 0 and ('n' + str(database)) in opened.stdout.splitlines()
        except sqlite3.Error:
            return False

    def diagnostics(pid):
        with (output / 'application-processes.log').open('w') as log:
            subprocess.run(['ps', '-axo', 'pid,ppid,command'], stdout=log, timeout=10)
            subprocess.run([str(lifecycle), 'inspect', str(install)], stdout=log, timeout=10)
        (output / 'startup-state.json').write_bytes(encoded(dict(pid=pid, database=str(database),
            databaseExists=database.exists(), supportFiles=[str(p.relative_to(users.parent))
                for p in users.parent.rglob('*') if p.is_file()])))
        if pid:
            with (output / 'application-sample.log').open('w') as log:
                subprocess.run(['sample', str(pid), '2'], stdout=log, stderr=subprocess.STDOUT, timeout=15)

    old = None
    old_pid = None
    try:
        print('Launching installed application through Launch Services', flush=True)
        old = subprocess.Popen(['open', '-n', '-W', '--stdout', str(output / 'old-application.log'),
            '--stderr', str(output / 'old-application.log'), str(install)])
        old_pid = wait_for(find, 'original application executable running')
        wait_for(lambda: database_ready(old_pid), 'original application database initialized and open')
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
            updater = subprocess.Popen([str(handoff), 'run', str(install), str(old_pid)], stdout=log, stderr=subprocess.STDOUT)
            try:
                def started():
                    path = workspace / 'started.json'
                    if not path.exists(): return False
                    state = json.loads(path.read_bytes())
                    return state.get('pid') == updater.pid and state.get('parent') == old_pid
                wait_for(started, 'native handoff')
                print('Requesting normal application exit and waiting for DMG replacement', flush=True)
                run(lifecycle, 'quit', old_pid)
                assert old.wait(timeout=30) == 0
                assert updater.wait(timeout=120) == 0
            finally:
                if updater.poll() is None: updater.kill(); updater.wait(timeout=10)
        new_pid = wait_for(find, 'updated app launched')
        assert new_pid != old_pid
        wait_for(lambda: database_ready(new_pid), 'updated application database initialized and open')
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
    except BaseException:
        diagnostics(find() or old_pid)
        raise
    finally:
        current = find()
        if current:
            subprocess.run([str(lifecycle), 'quit', str(current)], timeout=10)
            try:
                wait_for(lambda: find() is None, 'test application cleanup', timeout=10)
            except RuntimeError:
                # This PID was obtained from the unique disposable bundle path.
                os.kill(current, signal.SIGKILL)
        if old is not None and old.poll() is None:
            try: old.wait(timeout=10)
            except subprocess.TimeoutExpired:
                old.kill(); old.wait(timeout=10)


if __name__ == '__main__':
    main()
