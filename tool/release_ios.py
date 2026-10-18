"""Package a complete unsigned device app for user-managed signing, not updates."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import zipfile

from release_android import ReleaseCheckError
from update_manifest import APPLICATION_ID, identity, read_json

PREFIX = 'Payload/Runner.app/'
MACH_MAGIC = {b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}


def macho(raw, allow_signature=False):
    """Check every slice, including device platform, encryption and signature state."""
    try:
        if raw[:4] in {b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}:
            wide = raw[:4] == b'\xca\xfe\xba\xbf'
            count = struct.unpack_from('>I', raw, 4)[0]
            cpu, subtype = struct.unpack_from('>II', raw, 8)
            if count != 1 or cpu != 0x100000c or subtype & 0xffffff not in {0, 1}:
                raise ValueError
            offset, size = struct.unpack_from('>QQ' if wide else '>II', raw, 16)
            if offset < (40 if wide else 28) or size < 32 or offset + size > len(raw):
                raise ValueError
            raw = raw[offset:offset + size]
        magic, cpu, subtype, kind, count, length = struct.unpack_from('<6I', raw)
        if (magic != 0xfeedfacf or cpu != 0x100000c or subtype & 0xffffff not in {0, 1}
                or kind not in {2, 6, 8} or not 0 < count <= 1024 or 32 + length > len(raw)):
            raise ValueError
        position, device, signed, libraries = 32, False, False, []
        for _ in range(count):
            command, size = struct.unpack_from('<II', raw, position)
            if size < 8 or position + size > 32 + length:
                raise ValueError
            if command == 0x32:  # LC_BUILD_VERSION
                if size < 24 or struct.unpack_from('<I', raw, position + 8)[0] != 2:
                    raise ValueError
                device = True
            if command == 0x25:  # Older arm64 iOS framework: LC_VERSION_MIN_IPHONEOS
                if size < 16:
                    raise ValueError
                device = True
            if command in {0x21, 0x2c}:  # LC_ENCRYPTION_INFO[_64]
                if size < 20 or struct.unpack_from('<I', raw, position + 16)[0] != 0:
                    raise ValueError
            if command == 0x1d:
                signed = True
            if command in {0xc, 0x80000018, 0x8000001f}:  # load / weak / reexport dylib
                if size < 24:
                    raise ValueError
                start = struct.unpack_from('<I', raw, position + 8)[0]
                if not 24 <= start < size:
                    raise ValueError
                libraries.append(raw[position + start:position + size].split(b'\0', 1)[0].decode('utf-8'))
            position += size
        if position != 32 + length or not device or (signed and not allow_signature):
            raise ValueError
        return signed, libraries
    except (struct.error, ValueError, UnicodeDecodeError):
        raise ReleaseCheckError('Expected unsigned, unencrypted arm64 iOS device code') from None


def verify_archive(path, expected):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if not 1 <= len(entries) <= 20000:
            raise ReleaseCheckError('Invalid IPA entry count')
        files, seen, folded, total = {}, set(), set(), 0
        for entry in entries:
            name = entry.filename.rstrip('/')
            parts = name.split('/')
            mode = entry.external_attr >> 16
            total += entry.file_size
            if (not (name == 'Payload' or name == PREFIX.rstrip('/') or name.startswith(PREFIX))
                    or any(p in {'', '.', '..'} for p in parts) or '\\' in name
                    or any(ord(c) < 32 for c in name) or name in seen or name.casefold() in folded
                    or total > 2 * 1024**3 or mode & 0o7000 or entry.flag_bits & 1
                    or (mode and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)))):
                raise ReleaseCheckError('Invalid IPA path, permissions or size')
            if name in {'Payload', PREFIX.rstrip('/')} and not entry.is_dir():
                raise ReleaseCheckError('Invalid IPA root directory')
            seen.add(name)
            folded.add(name.casefold())
            if any(p == '_CodeSignature' or p.endswith('.dSYM') for p in parts) or Path(name).suffix.lower() in {
                    '.mobileprovision', '.p12', '.pfx', '.pem', '.key', '.p8', '.cer', '.crt', '.bcsymbolmap'}:
                raise ReleaseCheckError('Signing material, signature or debug symbols in IPA')
            if not entry.is_dir():
                files[name] = entry
        if any('/'.join(name.split('/')[:i]) in files for name in seen for i in range(1, len(name.split('/')))):
            raise ReleaseCheckError('IPA entry overlaps a file')
        def read(name):
            entry = files.get(PREFIX + name)
            if entry is None or entry.file_size == 0:
                raise ReleaseCheckError('Missing required iOS bundle resource: ' + name)
            return archive.read(entry)

        executables = set()
        for folder, identifier in [('', APPLICATION_ID), ('PlugIns/ShareExtension.appex/', APPLICATION_ID + '.ShareExtension')]:
            info = plistlib.loads(read(folder + 'Info.plist'))
            executable = info.get('CFBundleExecutable', '')
            if (info.get('CFBundleIdentifier') != identifier
                    or info.get('CFBundleShortVersionString') != expected['version']
                    or info.get('CFBundleVersion') != str(expected['build'])
                    or info.get('MinimumOSVersion') != '15.0'
                    or info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']
                    or not executable or '/' in executable or '\\' in executable):
                raise ReleaseCheckError('iOS application or extension identity mismatch')
            executables.add(PREFIX + folder + executable)
            macho(read(folder + executable))
            if not (files[PREFIX + folder + executable].external_attr >> 16) & 0o111:
                raise ReleaseCheckError('Missing iOS executable permission')
        read('Frameworks/Flutter.framework/Flutter')
        read('Frameworks/App.framework/App')
        for resource in ['AssetManifest.bin', 'FontManifest.json', 'NOTICES.Z']:
            read('Frameworks/App.framework/flutter_assets/' + resource)
        frameworks = {name.split('.framework/')[0] + '.framework/' for name in files if '.framework/' in name}
        for framework in frameworks:
            info = plistlib.loads(read(framework.removeprefix(PREFIX) + 'Info.plist'))
            executable = info.get('CFBundleExecutable', '')
            if not executable or '/' in executable or '\\' in executable:
                raise ReleaseCheckError('Invalid framework executable')
            binary = framework + executable
            if binary not in files:
                raise ReleaseCheckError('Missing framework executable')
            executables.add(binary)
        for name, entry in files.items():
            with archive.open(entry) as stream:
                magic = stream.read(4)
            if magic in MACH_MAGIC or name in executables:
                _, libraries = macho(archive.read(entry))
                for library in libraries:
                    if library.startswith('@rpath/') and not library.startswith('@rpath/libswift'):
                        if PREFIX + 'Frameworks/' + library.removeprefix('@rpath/') not in files:
                            raise ReleaseCheckError('Missing embedded iOS dependency: ' + library)
        for executable in executables:
            macho(archive.read(files[executable]))
        if {name.split('/')[3] for name in files if name.startswith(PREFIX + 'PlugIns/')} != {'ShareExtension.appex'}:
            raise ReleaseCheckError('Unexpected iOS extension')


def verify_assets(root, assets, tag, commit):
    from release_receipt import file_record
    expected = identity((root / 'pubspec.yaml').read_text(encoding='utf-8'), tag, commit)
    name = f'shiori-reader-{tag}-ios-arm64-unsigned.ipa'
    path = assets / name
    if path.is_symlink() or not 0 < path.stat().st_size <= 2 * 1024**3:
        raise ReleaseCheckError('Invalid iOS release archive')
    value = read_json((assets / 'receipts/ios-arm64.json').read_bytes())
    if value != dict(schemaVersion=1, identity=expected, platform='ios-arm64', packages=[file_record(path)]):
        raise ReleaseCheckError('iOS release metadata mismatch')
    verify_archive(path, expected)
    return {name}


def package(root, app, assets, tag, commit):
    expected = identity((root / 'pubspec.yaml').read_text(encoding='utf-8'), tag, commit)
    if app.name != 'Runner.app' or not app.is_dir() or app.is_symlink():
        raise ReleaseCheckError('Expected complete Runner.app')
    assets.mkdir(parents=True, exist_ok=True)
    name = f'shiori-reader-{tag}-ios-arm64-unsigned.ipa'
    with tempfile.TemporaryDirectory(prefix='shiori-ios-package-') as temporary:
        staged = Path(temporary) / 'Payload/Runner.app'
        shutil.copytree(app, staged, symlinks=True)
        entries = list(staged.rglob('*'))
        if any(p.is_symlink() for p in entries):
            raise ReleaseCheckError('Unexpected symbolic link in iOS bundle')
        # Only remove signatures from recognized code bundles in this disposable copy.
        bundles = sorted([staged] + [p for p in entries if p.is_dir() and p.suffix in {'.framework', '.appex'}],
                         key=lambda p: len(p.parts), reverse=True)
        for bundle in bundles:
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            executable = info.get('CFBundleExecutable', '')
            if not executable or '/' in executable or '\\' in executable:
                raise ReleaseCheckError('Invalid code bundle executable')
            binary = bundle / executable
            if macho(binary.read_bytes(), allow_signature=True)[0] or (bundle / '_CodeSignature').exists():
                subprocess.run(['codesign', '--remove-signature', str(bundle)], check=True)
            # A previous local signed build may leave these despite --no-codesign.
            (bundle / 'embedded.mobileprovision').unlink(missing_ok=True)
        for path in entries:
            if path.is_file():
                with path.open('rb') as source:
                    code = source.read(4) in MACH_MAGIC
                if code and macho(path.read_bytes(), allow_signature=True)[0]:
                    subprocess.run(['codesign', '--remove-signature', str(path)], check=True)
        with zipfile.ZipFile(assets / name, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(staged.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(temporary).as_posix())
    verify_archive(assets / name, expected)
    from release_receipt import write_receipt
    write_receipt(assets, 'ios-arm64', expected, [assets / name])
    verify_assets(root, assets, tag, commit)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['package', 'verify'])
    parser.add_argument('--app', type=Path, default=Path('build/ios/iphoneos/Runner.app'))
    parser.add_argument('--assets', type=Path, default=Path('build/ios-release-assets'))
    args = parser.parse_args()
    try:
        if args.mode == 'package':
            package(Path.cwd(), args.app, args.assets, os.environ['GITHUB_REF_NAME'], os.environ['GITHUB_SHA'])
        else:
            verify_assets(Path.cwd(), args.assets, os.environ['GITHUB_REF_NAME'], os.environ['GITHUB_SHA'])
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, subprocess.CalledProcessError, ReleaseCheckError) as error:
        raise SystemExit('iOS unsigned packaging failed: ' + str(error)) from None
