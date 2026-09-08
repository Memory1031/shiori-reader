"""Build isolated, pinned EPUB comparison workers; never edit app dependencies."""
import argparse
import json
from pathlib import Path
import subprocess
import os


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dart', required=True, help='Absolute Dart SDK executable')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    templates = root / 'tool/epub_compare'
    output = root / '.tooling/epub-compare'
    dependencies = {
        'epubx': {'epubx': '4.0.0', 'crypto': '3.0.7'},
        'epub_parser': {'epub_parser': '3.0.1', 'crypto': '3.0.7'},
        'shiori': {'archive': '4.2.0', 'crypto': '3.0.7', 'html': '0.15.7', 'xml': '6.6.1'},
    }
    for name, deps in dependencies.items():
        directory = output / name
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'pubspec.yaml').write_text(
            f"name: {name}_comparison\nenvironment:\n  sdk: '>=3.10.3 <3.11.0'\ndependencies:\n" +
            ''.join(f'  {key}: {value}\n' for key, value in deps.items()), encoding='utf-8')
        subprocess.run([args.dart, 'pub', 'get'], cwd=directory, check=True)
        if name == 'shiori':
            config_path = directory / '.dart_tool/package_config.json'
            config = json.loads(config_path.read_text(encoding='utf-8'))
            config['packages'] = [p for p in config['packages'] if p['name'] != 'shiori']
            config['packages'].append({'name': 'shiori', 'rootUri': root.as_uri() + '/',
                'packageUri': 'lib/', 'languageVersion': '3.10'})
            config_path.write_text(json.dumps(config), encoding='utf-8')
        template = templates / ('shiori.dart.template' if name == 'shiori' else 'library.dart.template')
        (directory / 'worker.dart').write_text(template.read_text(encoding='utf-8').replace('LIBRARY', name), encoding='utf-8')
        executable = output / (name + ('.exe' if os.name == 'nt' else ''))
        subprocess.run([args.dart, 'compile', 'exe', 'worker.dart', '-o', str(executable)], cwd=directory, check=True)


if __name__ == '__main__':
    main()
