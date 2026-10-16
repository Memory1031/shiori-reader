"""Package unsigned macOS bundles and produce a separate signed update feed."""
import argparse
import base64
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import tempfile
import subprocess
import zipfile

from release_android import ReleaseCheckError
from update_manifest import (APPLICATION_ID, ALGORITHM, IDENTITY_ASSET,
                             check_bundled, encoded, identity, public_key,
                             read_json, sign_manifest, sha)

BUNDLE_IDENTITY = 'Shiori.app/Contents/Frameworks/App.framework/Resources/flutter_assets/' + IDENTITY_ASSET


def verify_archive(path, expected, key):
    with zipfile.ZipFile(path) as archive:
        seen, links, total = set(), [], 0
        entries = archive.infolist()
        if not 1 <= len(entries) <= 20000:
            raise ReleaseCheckError('Invalid macOS archive size')
        for entry in entries:
            name = entry.filename.rstrip('/')
            parts = name.split('/')
            if (not name or parts[0] != 'Shiori.app' or any(p in ('', '.', '..') for p in parts)
                    or '\\' in name or '\n' in name or name in seen):
                raise ReleaseCheckError('Invalid macOS archive path')
            seen.add(name)
            mode = entry.external_attr >> 16
            total += entry.file_size
            if total > 2 * 1024**3 or mode & 0o7000:
                raise ReleaseCheckError('Invalid macOS archive permissions or size')
            if stat.S_ISLNK(mode):
                target = archive.read(entry).decode('utf-8')
                resolved = os.path.normpath(str(PurePosixPath(name).parent / target))
                if target.startswith('/') or not resolved.startswith('Shiori.app/'):
                    raise ReleaseCheckError('Escaping macOS symbolic link')
                links.append(name)
            elif mode and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ReleaseCheckError('Unsupported macOS archive entry')
        for name in seen:
            if any(name.startswith(link + '/') for link in links):
                raise ReleaseCheckError('Archive writes through a symbolic link')
        info = plistlib.loads(archive.read('Shiori.app/Contents/Info.plist'))
        if (info['CFBundleIdentifier'] != APPLICATION_ID
                or info['CFBundleShortVersionString'] != expected['version']
                or int(info['CFBundleVersion']) != expected['build']):
            raise ReleaseCheckError('macOS bundle identity mismatch')
        for name in ['Shiori', 'shiori-updater']:
            entry = archive.getinfo('Shiori.app/Contents/MacOS/' + name)
            if not (entry.external_attr >> 16) & 0o111:
                raise ReleaseCheckError('macOS executable permission missing')
        # macOS frameworks store Resources behind a versioned symlink.
        identity_path = BUNDLE_IDENTITY if BUNDLE_IDENTITY in seen else BUNDLE_IDENTITY.replace('/App.framework/Resources/', '/App.framework/Versions/A/Resources/')
        check_bundled(archive.read(identity_path), expected, key)


def create_manifest(root, assets, tag, commit, key):
    expected = identity((root / 'pubspec.yaml').read_text(), tag, commit)
    key = public_key(key)
    name = f'shiori-reader-{tag}-macos-universal.zip'
    path = assets / name
    metadata = read_json((assets / 'release-info-macos-universal.json').read_bytes())
    dmg = metadata.pop('dmg', None)
    if (path.is_symlink() or not 0 < path.stat().st_size <= 2 * 1024**3
            or metadata != dict(tag=tag, commit=commit, versionName=expected['version'],
                                versionCode=expected['build'], platform='macos-universal',
                                archive=name, sha256=sha(path))):
        raise ReleaseCheckError('macOS release metadata mismatch')
    verify_archive(path, expected, key)
    result = dict(schemaVersion=1, algorithm=ALGORITHM, keyId=key['keyId'],
                  **expected, assets=[dict(platform='macos-universal', name=name,
                  size=path.stat().st_size, sha256=sha(path), minimumSystem='12.0', updaterProtocol=1)])
    if dmg is not None:
        installer = assets / f'shiori-reader-{tag}-macos-universal.dmg'
        if installer.is_symlink() or dmg != dict(name=installer.name, size=installer.stat().st_size, sha256=sha(installer)):
            raise ReleaseCheckError('macOS disk image mismatch')
        result['installer'] = dmg
    return encoded(result)


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
    expected = identity((root / 'pubspec.yaml').read_text(), tag, commit)
    for name in ['Shiori', 'shiori-updater']:
        archs = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS' / name)], text=True).split()
        if set(archs) != {'arm64', 'x86_64'}:
            raise ReleaseCheckError('Expected a universal macOS executable')
    sign_locally(app)
    assets.mkdir(parents=True, exist_ok=True)
    name = f'shiori-reader-{tag}-macos-universal.zip'
    output = assets / name
    if output.exists():
        raise ReleaseCheckError('Refusing to replace an existing release asset')
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(app), str(output)], check=True)
    verify_archive(output, expected, key)
    metadata = dict(tag=tag, commit=commit, versionName=expected['version'],
                    versionCode=expected['build'], platform='macos-universal', archive=name, sha256=sha(output))
    dmg = assets / f'shiori-reader-{tag}-macos-universal.dmg'
    with tempfile.TemporaryDirectory(prefix='shiori-dmg-') as directory:
        stage = Path(directory)
        subprocess.run(['ditto', str(app), str(stage / 'Shiori.app')], check=True)
        (stage / 'Applications').symlink_to('/Applications')
        subprocess.run(['hdiutil', 'create', '-volname', 'Shiori', '-srcfolder', str(stage), '-format', 'UDZO', str(dmg)], check=True)
    metadata['dmg'] = dict(name=dmg.name, size=dmg.stat().st_size, sha256=sha(dmg))
    (assets / 'release-info-macos-universal.json').write_bytes(encoded(metadata))
    (assets / 'SHA256SUMS-macos-universal.txt').write_text(f'{sha(output)}  {name}\n{sha(dmg)}  {dmg.name}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['package', 'manifest'])
    parser.add_argument('--app', type=Path, default=Path('build/macos/Build/Products/Release/Shiori.app'))
    parser.add_argument('--assets', type=Path, default=Path('build/release-assets'))
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME'))
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    key = public_key(read_json(os.environ.get('UPDATE_PUBLIC_KEY_JSON', '{}')))
    if args.command == 'package':
        package(root, args.app, args.assets, args.tag, args.commit, key)
    else:
        raw = create_manifest(root, args.assets, args.tag, args.commit, key)
        secret = base64.b64decode(os.environ.get('UPDATE_SIGNING_KEY_PEM_B64', ''), validate=True)
        signature = sign_manifest(raw, secret, key)
        (args.assets / 'update-manifest-macos.json').write_bytes(raw)
        (args.assets / 'update-manifest-macos.sig').write_bytes(signature)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, subprocess.CalledProcessError):
        raise SystemExit('macOS release validation failed; check the bundle, identity and update configuration.')
