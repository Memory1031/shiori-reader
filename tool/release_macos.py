"""Build a verified universal DMG for first installation and signed updates."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import tempfile
import subprocess

from release_android import ReleaseCheckError
from update_manifest import (APPLICATION_ID, IDENTITY_ASSET, check_bundled,
                             identity, public_key, read_json)
from release_receipt import write_receipt

BUNDLE_IDENTITY = 'Shiori.app/Contents/Frameworks/App.framework/Resources/flutter_assets/' + IDENTITY_ASSET


def verify_bundle(app, expected, key):
    root = app.resolve()
    seen, total = set(), 0
    for path in [app, *app.rglob('*')]:
        mode = path.lstat()
        name = path.relative_to(app.parent).as_posix()
        if (name in seen or len(seen) >= 20000 or mode.st_mode & 0o7000
                or any(p in ('', '.', '..') for p in name.split('/'))
                or '\\' in name or '\n' in name):
            raise ReleaseCheckError('Invalid macOS bundle entry')
        seen.add(name)
        if path.is_symlink():
            target = os.readlink(path)
            if os.path.isabs(target) or not path.resolve().is_relative_to(root):
                raise ReleaseCheckError('Escaping macOS symbolic link')
        elif stat.S_ISREG(mode.st_mode):
            total += mode.st_size
            if mode.st_nlink != 1 or total > 2 * 1024**3:
                raise ReleaseCheckError('Invalid macOS bundle size or hard link')
        elif not stat.S_ISDIR(mode.st_mode):
            raise ReleaseCheckError('Unsupported macOS bundle entry')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (info['CFBundleIdentifier'] != APPLICATION_ID
            or info['CFBundleShortVersionString'] != expected['version']
            or str(info['CFBundleVersion']) != str(expected['build'])):
        raise ReleaseCheckError('macOS bundle identity mismatch')
    for name in ['Shiori', 'shiori-updater']:
        if not (app / 'Contents/MacOS' / name).stat().st_mode & 0o111:
            raise ReleaseCheckError('macOS executable permission missing')
    check_bundled((app.parent / BUNDLE_IDENTITY).read_bytes(), expected, key)


def sign_locally(app):
    # Sign nested code first, then seal bundles. No account or identity required.
    magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
    entries = sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True)
    for path in entries:
        if path.is_file() and not path.is_symlink() and path != app / 'Contents/MacOS/Shiori':
            with path.open('rb') as source:
                is_code = source.read(4) in magic
            if is_code:
                if set(subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()) != {'arm64', 'x86_64'}:
                    raise ReleaseCheckError('Expected universal macOS nested code')
                subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(path)], check=True)
    for path in [p for p in entries if p.is_dir() and not p.is_symlink() and p.suffix in {'.framework', '.xpc', '.bundle', '.app'}] + [app]:
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(path)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


def package(root, app, assets, tag, commit, key):
    if app.name != 'Shiori.app' or not app.is_dir() or app.is_symlink():
        raise ReleaseCheckError('Expected the complete Shiori.app bundle')
    expected = identity((root / 'pubspec.yaml').read_text(encoding='utf-8'), tag, commit)
    for name in ['Shiori', 'shiori-updater']:
        archs = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS' / name)], text=True).split()
        if set(archs) != {'arm64', 'x86_64'}:
            raise ReleaseCheckError('Expected a universal macOS executable')
    sign_locally(app)
    assets.mkdir(parents=True, exist_ok=True)
    verify_bundle(app, expected, key)
    dmg = assets / f'shiori-reader-{tag}-macos-universal.dmg'
    if dmg.exists():
        raise ReleaseCheckError('Refusing to replace an existing release asset')
    with tempfile.TemporaryDirectory(prefix='shiori-dmg-') as directory:
        stage = Path(directory)
        subprocess.run(['ditto', str(app), str(stage / 'Shiori.app')], check=True)
        (stage / 'Applications').symlink_to('/Applications')
        subprocess.run(['hdiutil', 'create', '-volname', 'Shiori', '-srcfolder', str(stage), '-format', 'UDZO', str(dmg)], check=True)
    # Validate the actual disk image, not just the pre-image staging bundle.
    with tempfile.TemporaryDirectory(prefix='shiori-dmg-verify-') as directory:
        mount = Path(directory).resolve() / 'volume'
        mount.mkdir()
        try:
            result = subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse',
                '-noautoopen', '-mountpoint', str(mount), '-plist', str(dmg)])
            entities = plistlib.loads(result)['system-entities']
            if not any(e.get('mount-point') == str(mount) for e in entities):
                raise ReleaseCheckError('Unexpected DMG mount')
            verify_bundle(mount / 'Shiori.app', expected, key)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mount / 'Shiori.app')], check=True)
        finally:
            if os.path.ismount(mount):
                subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
    write_receipt(assets, 'macos-universal', expected, [dmg])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['package'])
    parser.add_argument('--app', type=Path, default=Path('build/macos/Build/Products/Release/Shiori.app'))
    parser.add_argument('--assets', type=Path, default=Path('build/release-assets'))
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME'))
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    key = public_key(read_json(os.environ.get('UPDATE_PUBLIC_KEY_JSON', '{}')))
    package(root, args.app, args.assets, args.tag, args.commit, key)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError):
        raise SystemExit('macOS release validation failed; check the bundle, identity and update configuration.')
