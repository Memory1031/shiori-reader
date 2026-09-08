"""Read-only explicit sample comparison. No book text/images are written out.

Expects independently compiled shiori/epubx/epub_parser executables in --bin.
See README.md for build instructions. Standard Python library only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import posixpath
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile


def path_at(base, reference):
    return posixpath.normpath(posixpath.join(base, urllib.parse.unquote(urllib.parse.urlsplit(reference.strip()).path)))


def source_structure(path):
    with zipfile.ZipFile(path) as archive:
        container = ET.fromstring(archive.read('META-INF/container.xml'))
        rootfile = next(e.attrib['full-path'] for e in container.iter() if e.tag.split('}')[-1] == 'rootfile')
        package = ET.fromstring(archive.read(rootfile))
        base = posixpath.dirname(rootfile)
        items = {e.attrib['id']: e.attrib for e in package.iter() if e.tag.split('}')[-1] == 'item'}
        spine = [path_at(base, items[e.attrib['idref']]['href']) for e in package.iter() if e.tag.split('}')[-1] == 'itemref']
        resources = {}
        for item in items.values():
            mime = item.get('media-type', '')
            if mime == 'application/xhtml+xml' or mime.startswith('image/'):
                target = path_at(base, item['href'])
                raw = archive.read(target)
                kind = 'html' if mime == 'application/xhtml+xml' else 'image'
                if kind == 'html':
                    raw = raw.decode('utf-8-sig').encode('utf-8')
                resources[target] = {'kind': kind, 'sha256': hashlib.sha256(raw).hexdigest()}
        return {'spine': spine, 'resources': resources,
                'encryptionDeclaration': 'META-INF/encryption.xml' in archive.namelist()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--samples', required=True)
    parser.add_argument('--bin', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    paths = json.loads(Path(args.samples).read_text(encoding='utf-8-sig'))
    results = []
    for path in paths:
        entry = {'file': Path(path).name}
        if not Path(path).is_file():
            entry['status'] = 'input-missing'
            results.append(entry)
            continue
        entry['sha256'] = hashlib.sha256(Path(path).read_bytes()).hexdigest()
        try:
            source = source_structure(path)
            entry['source'] = {'spineCount': len(source['spine']),
                'htmlCount': sum(x['kind'] == 'html' for x in source['resources'].values()),
                'imageCount': sum(x['kind'] == 'image' for x in source['resources'].values()),
                'encryptionDeclaration': source['encryptionDeclaration']}
        except Exception as error:
            source = None
            entry['source'] = {'errorType': type(error).__name__}
        for library in ('shiori', 'epubx', 'epub_parser'):
            executable = Path(args.bin) / (library + ('.exe' if __import__('os').name == 'nt' else ''))
            try:
                process = subprocess.run([str(executable.resolve()), path], capture_output=True, timeout=60)
                if process.returncode:
                    entry[library] = {'status': 'process-failed', 'exitCode': process.returncode}
                    continue
                result = json.loads(process.stdout.decode('utf-8').splitlines()[-1])
                for key in ('file', 'sha256', 'bytes'):
                    result.pop(key, None)
                if source and result['status'] == 'parsed' and library != 'shiori':
                    extracted = {r['path']: r for r in result['resources']}
                    result['missingResources'] = [p for p in source['resources'] if p not in extracted]
                    result['differentResources'] = [p for p, r in source['resources'].items()
                        if p in extracted and r['sha256'] != extracted[p]['sha256']]
                    result['spineMatches'] = source['spine'] == result['spine']
                    result['navMissingDocuments'] = sum(n['path'] not in extracted for n in result['navigation'])
                entry[library] = result
            except subprocess.TimeoutExpired:
                entry[library] = {'status': 'timeout'}
        results.append(entry)
        print(f"{len(results)}/{len(paths)}: " + ', '.join(f"{k}={entry[k]['status']}" for k in ('shiori','epubx','epub_parser')), flush=True)
        Path(args.output).write_text(json.dumps({'samples': results}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    Path(args.output).write_text(json.dumps({'samples': results}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
