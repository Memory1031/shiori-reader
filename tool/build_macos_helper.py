"""Build the installed macOS updater with the application's pinned update trust."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def build(root, output, architectures, testing=False):
    identity = json.loads((root / 'assets/release/build-info.json').read_text())
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = tempfile.TemporaryDirectory(prefix='shiori-macos-trust-')
    header = Path(temporary.name) / 'UpdateTrust.h'
    encoded = json.dumps(identity, separators=(',', ':'))
    header.write_text('static const char *SHIORI_UPDATE_TRUST = ' + json.dumps(encoded) + ';\n')
    command = ['xcrun', 'clang++', '-std=c++17', '-fobjc-arc', '-Wno-deprecated-declarations',
               '-mmacosx-version-min=12.0', '-I', str(header.parent),
               str(root / 'macos/Updater/main.mm'), '-o', str(output),
               '-framework', 'AppKit', '-framework', 'Security', '-larchive']
    for arch in architectures:
        command += ['-arch', arch]
    if testing:
        command += ['-DSHIORI_UPDATER_TESTING']
    try:
        subprocess.run(command, check=True)
    finally:
        temporary.cleanup()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--arch', nargs='+', default=['arm64', 'x86_64'])
    args = parser.parse_args()
    build(Path(__file__).resolve().parent.parent, args.output, args.arch)
