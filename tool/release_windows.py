"""Build a checked Windows x64 ZIP; never create a tag or publish a release."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import zipfile

from release_android import ReleaseCheckError, version


RUNTIME = (
    'shiori.exe', 'shiori-updater.exe', 'flutter_windows.dll', 'flutter_inappwebview_windows_plugin.dll',
    'file_selector_windows_plugin.dll', 'WebView2Loader.dll', 'sqlite3.dll',
    'dartjni.dll', 'data/app.so', 'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin', 'data/flutter_assets/NOTICES.Z',
)
CRT = ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
# Versions match the locked Windows WebView fork's native CMake dependencies.
NATIVE_PACKAGES = Path('build/windows/x64/packages/flutter_inappwebview_windows/1.0.231216.1-1.0.2792.45-3.11.2')
NATIVE_NOTICES = ('Microsoft.Web.WebView2/LICENSE.txt', 'Microsoft.Web.WebView2/NOTICE.txt',
                  'Microsoft.Windows.ImplementationLibrary/LICENSE')
# Every shipped path, itself included: the next updater replaces exactly these.
PROGRAM_FILES = 'program-files.txt'
BUILD_INFO = 'data/flutter_assets/assets/release/build-info.json'


def exe_metadata(executable):
    environment = {**os.environ, 'SHIORI_RELEASE_EXE': str(executable)}
    command = ('$v = [Diagnostics.FileVersionInfo]::GetVersionInfo($env:SHIORI_RELEASE_EXE); '
               '$v | Select-Object ProductName, OriginalFilename, ProductVersion, '
               'FileMajorPart, FileMinorPart, FileBuildPart, FilePrivatePart, IsDebug | ConvertTo-Json')
    result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
                            env=environment, capture_output=True, check=False)
    if result.returncode:
        raise ReleaseCheckError('Cannot read Windows executable version metadata')
    return json.loads(result.stdout.decode('utf-8-sig'))


def verify_exe(executable, name, number, metadata):
    with executable.open('rb') as binary:
        header = binary.read(64)
        if len(header) != 64 or header[:2] != b'MZ':
            raise ReleaseCheckError('Windows executable is not PE')
        binary.seek(struct.unpack_from('<I', header, 60)[0])
        if binary.read(6) != b'PE\0\0\x64\x86':
            raise ReleaseCheckError('Windows executable must be x64')
    expected = (*map(int, name.split('-')[0].split('.')), int(number))
    actual = tuple(metadata[key] for key in
                   ('FileMajorPart', 'FileMinorPart', 'FileBuildPart', 'FilePrivatePart'))
    if (actual != expected or metadata['ProductVersion'] != f'{name}+{number}'
            or metadata['ProductName'] != 'Shiori'
            or metadata['OriginalFilename'] != 'shiori.exe' or metadata['IsDebug']):
        raise ReleaseCheckError('Windows executable identity/version/debug flag does not match release')


def verify_updater(bundle):
    # The updater must trust the same key the application bundles.
    if not (bundle / BUILD_INFO).is_file():
        raise ReleaseCheckError('Missing bundled build identity')
    bundled = json.loads((bundle / BUILD_INFO).read_bytes())
    modulus = bundled.get('publicKey', {}).get('modulus')
    if modulus and modulus.encode('ascii') not in (bundle / 'shiori-updater.exe').read_bytes():
        raise ReleaseCheckError('Windows updater does not embed the bundled update key')


def package(root, bundle, crt, output, tag, commit, metadata_reader=exe_metadata):
    name, number = version((root / 'pubspec.yaml').read_text(encoding='utf-8'), tag)
    if not re.fullmatch(r'[0-9a-fA-F]{40}', commit):
        raise ReleaseCheckError('A full source commit SHA is required')
    bundle, crt, output = bundle.resolve(), crt.resolve(), output.resolve()
    if output == bundle or bundle in output.parents:
        raise ReleaseCheckError('Output directory must be outside the runtime bundle')
    files = {}

    def include(path, archive_name):
        if path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
            raise ReleaseCheckError('Release bundle must not contain links')
        if not path.is_file() or path.stat().st_size == 0:
            raise ReleaseCheckError('Missing or empty runtime file: ' + archive_name)
        files[archive_name] = path

    for relative in RUNTIME:
        include(bundle / relative, relative)
    verify_exe(bundle / 'shiori.exe', name, number, metadata_reader(bundle / 'shiori.exe'))
    verify_updater(bundle)
    for path in sorted(bundle.glob('*.dll')):
        include(path, path.name)
    for path in sorted((bundle / 'data').rglob('*')):
        if path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
            raise ReleaseCheckError('Release data must not contain links')
        if path.is_file():
            # Flutter may emit empty asset files; only required files must be nonempty.
            files[path.relative_to(bundle).as_posix()] = path
    for dll in CRT:
        include(crt / dll, dll)
    include(root / 'LICENSE', 'LICENSE')
    for notice in NATIVE_NOTICES:
        include(root / NATIVE_PACKAGES / notice, 'licenses/' + notice)
    include(root / 'tool/licenses/nlohmann-json-3.11.2-LICENSE.MIT',
            'licenses/nlohmann-json-3.11.2-LICENSE.MIT')
    output.mkdir(parents=True, exist_ok=True)
    listing = ''.join(relative + '\n' for relative in sorted([*files, PROGRAM_FILES]))
    archive = output / f'shiori-reader-{tag}-windows-x64.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
        for relative, path in sorted(files.items()):
            zipped.write(path, relative)
        zipped.writestr(PROGRAM_FILES, listing.encode('utf-8'))
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None:
            raise ReleaseCheckError('Windows ZIP integrity check failed')
    with archive.open('rb') as binary:
        digest = hashlib.file_digest(binary, 'sha256').hexdigest()
    (output / 'SHA256SUMS-windows-x64.txt').write_text(
        f'{digest}  {archive.name}\n', encoding='ascii')
    (output / 'release-info-windows-x64.json').write_text(json.dumps({
        'tag': tag, 'commit': commit, 'versionName': name, 'versionCode': int(number),
        'platform': 'windows-x64', 'archive': archive.name, 'sha256': digest,
        'signed': False,
    }, indent=2) + '\n', encoding='utf-8')
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME', ''))
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA', ''))
    parser.add_argument('--bundle', type=Path, default=Path('build/windows/x64/runner/Release'))
    parser.add_argument('--crt-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('build/windows-release-assets'))
    args = parser.parse_args()
    archive = package(Path.cwd(), args.bundle, args.crt_dir, args.output, args.tag, args.commit)
    print('Windows ZIP verified: ' + archive.name)


if __name__ == '__main__':
    try:
        main()
    except (ReleaseCheckError, OSError, ValueError, KeyError) as error:
        print('Windows release check failed: ' +
              (str(error) if isinstance(error, ReleaseCheckError) else 'invalid runtime or metadata'),
              file=sys.stderr)
        sys.exit(1)
