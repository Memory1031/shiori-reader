"""Offline native intake smoke test. Requires installed app + fixture APK on a test emulator."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--adb', default='adb')
parser.add_argument('--system-picker', action='store_true')
parser.add_argument('--files-only', action='store_true')
args = parser.parse_args()
evidence = Path('.tooling/evidence')
evidence.mkdir(parents=True, exist_ok=True)
prefix = [args.adb, '-s', args.device]

def adb(*command, check=True):
    result = subprocess.run(prefix + list(command), capture_output=True, timeout=30)
    if check and result.returncode:
        raise AssertionError(result.stderr.decode(errors='replace'))
    return result.stdout

def receipt():
    raw = adb('shell', 'run-as', 'dev.shiori.reader', 'cat',
              'no_backup/import-inbox/pending/receipt.json', check=False)
    try:
        return json.loads(raw)
    except ValueError:
        return None

def wait(test, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = test()
        if result:
            return result
        time.sleep(.3)
    raise AssertionError('Timed out: ' + repr(test))

def snapshot():
    adb('shell', 'uiautomator', 'dump', '/sdcard/local002-window.xml')
    raw = adb('shell', 'cat', '/sdcard/local002-window.xml')
    (evidence / 'local002-android-ui.xml').write_bytes(raw)
    return ET.fromstring(raw)

def text_of(node):
    return node.get('text', '') or node.get('content-desc', '')

def tap(*labels, last=False):
    def find():
        nodes = [n for n in snapshot().iter('node')
                 if text_of(n) in labels and n.get('enabled') == 'true']
        return (nodes[-1] if last else nodes[0]) if nodes else None
    # ElementTree leaves are falsey, so do not use truthiness for matching nodes.
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        node = find()
        if node is not None:
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            return
    raise AssertionError('Missing control: ' + repr(labels))

def visible(*fragments):
    return any(any(s in text_of(n) for s in fragments) for n in snapshot().iter('node'))

def send(mode, name):
    adb('shell', 'am', 'start', '-n', 'dev.shiori.importfixture/.SendActivity',
        '--es', 'mode', mode, '--es', 'name', name)

def launch():
    adb('shell', 'am', 'start', '-n', 'dev.shiori.reader/.MainActivity')

def cancel():
    tap('Cancel', '取消')
    wait(lambda: receipt() is None)

launch()
if receipt() is not None:
    tap('Review', '查看')
    cancel()

if args.files_only:
    for suffix, content in [('txt', b'Offline Files app fixture.'), ('epub', b'PK\x03\x04intake fixture')]:
        name = 'local002-files.' + suffix
        source = evidence / name
        source.write_bytes(content)
        adb('push', str(source), '/sdcard/Download/' + name)
        adb('shell', 'am', 'start', '-n', 'com.google.android.documentsui/com.android.documentsui.files.FilesActivity')
        wait(lambda: visible('Show roots'))
        tap('Show roots')
        tap('Downloads', last=True)
        wait(lambda: visible('Files in Downloads'))
        tap(name)
        wait(lambda: receipt() is not None or visible('Open with'))
        if receipt() is None:
            if any(text_of(n) == 'Shiori' for n in snapshot().iter('node')):
                tap('Shiori')
            tap('Just once')
        wait(lambda: receipt() is not None and receipt()['name'] == name)
        wait(lambda: visible('A file is ready to import', '有文件等待导入'))
        assert adb('exec-out', 'run-as', 'dev.shiori.reader', 'cat',
                   'no_backup/import-inbox/pending/payload') == content
        tap('Review', '查看')
        cancel()
        adb('shell', 'rm', '/sdcard/Download/' + name)
        print('PASS: system Files external open ' + suffix, flush=True)
    raise SystemExit(0)

if args.system_picker:
    name = 'local002-system.txt'
    source = evidence / name
    source.write_bytes(b'Offline system file picker fixture.\n')
    adb('push', str(source), '/sdcard/Download/' + name)
    tap('Import book', '导入书籍')
    tap('Choose file', '选择文件')
    wait(lambda: any(n.get('package', '').endswith('documentsui') for n in snapshot().iter('node')))
    if not visible(name):
        tap('Show roots')
        tap('Downloads', last=True)
    tap(name)
    wait(lambda: receipt() is not None and receipt()['name'] == name)
    wait(lambda: visible(name))
    assert adb('exec-out', 'run-as', 'dev.shiori.reader', 'cat',
               'no_backup/import-inbox/pending/payload') == source.read_bytes()
    (evidence / 'local002-android-system-picker.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    cancel()
    print('PASS: real system Downloads selection, UI handoff, identical bytes and cancel cleanup', flush=True)
    raise SystemExit(0)

for index, (mode, suffix) in enumerate([('view', 'txt'), ('send', 'epub'), ('view', 'epub'), ('send', 'txt')]):
    assert receipt() is None, 'Handle an existing pending file before this test.'
    name = f'local002-{index}.{suffix}'
    if index == 0:
        adb('shell', 'am', 'force-stop', 'dev.shiori.reader')
    send(mode, name)
    original = wait(receipt)
    assert original['name'] == name
    payload = adb('exec-out', 'run-as', 'dev.shiori.reader', 'cat', 'no_backup/import-inbox/pending/payload')
    assert len(payload) == original['size'] and len(payload) > 0
    # Repeated delivery must not replace the existing pending receipt.
    send(mode, name)
    time.sleep(.8)
    assert receipt()['id'] == original['id']
    send('delete', name)
    assert adb('exec-out', 'run-as', 'dev.shiori.reader', 'cat',
               'no_backup/import-inbox/pending/payload') == payload
    if index == 0:
        adb('shell', 'am', 'force-stop', 'dev.shiori.reader')
    launch()
    wait(lambda: visible(name))
    tap('Review', '查看')
    tap('Import', 'Retry', '导入', '重试')
    wait(lambda: visible('cannot parse this format yet', '暂不支持解析'))
    cancel()
    print(f'PASS: {mode} {suffix}, temporary URI copy, source removal, duplicate receipt protection', flush=True)

for mode, name, message in [
    ('multiple', 'multiple.txt', ('Only one file', '每次仅支持')),
    ('missing', 'missing.txt', ('could not be read', '无法读取')),
    ('send', 'unsupported.pdf', ('Choose a TXT', '仅支持', '请选择 TXT')),
]:
    send(mode, name)
    tap('Review', '查看')
    wait(lambda: visible(*message))
    assert receipt() is None
    cancel()
    print('PASS: recoverable ' + mode + ' ' + name, flush=True)

tap('Import book', '导入书籍')
tap('Choose file', '选择文件')
wait(lambda: any(n.get('package') == 'com.google.android.documentsui' or n.get('package') == 'com.android.documentsui'
                 for n in snapshot().iter('node')))
adb('shell', 'input', 'keyevent', '4')
wait(lambda: visible('Choose file', '选择文件'))
assert receipt() is None
cancel()
print('PASS: native document picker cancellation', flush=True)
(evidence / 'local002-android-final.png').write_bytes(adb('exec-out', 'screencap', '-p'))
