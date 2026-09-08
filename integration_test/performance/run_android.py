"""Run the isolated TEST-003 profile APK, copy evidence, restore a supplied APK.
No uninstall, clear-data, device setting change, or live Source request.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--adb', required=True)
parser.add_argument('--serial', required=True)
parser.add_argument('--profile', required=True)
parser.add_argument('--restore', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--images-only', action='store_true')
parser.add_argument('--suite-only', action='store_true')
parser.add_argument('--scroll-only', action='store_true')
args = parser.parse_args()
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
app = 'dev.shiori.reader'
root = 'files/test003'


def adb(*command, check=True):
    return subprocess.run([args.adb, '-s', args.serial, *command],
                          check=check, text=True, capture_output=True, timeout=60)


def file(name):
    result = adb('shell', 'run-as', app, 'cat', f'{root}/{name}', check=False)
    return result.stdout if result.returncode == 0 else None


def launch():
    adb('shell', 'am', 'force-stop', app)
    return adb('shell', 'am', 'start', '-W', '-n', f'{app}/.MainActivity').stdout


def poll_report(timeout):
    deadline = time.monotonic() + timeout
    last_notice = time.monotonic()
    while time.monotonic() < deadline:
        raw = file('report.json')
        try:
            report = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            report = {}
        if report.get('status') in ('COLD_PASS', 'PASS', 'FAIL'):
            return report
        if time.monotonic() - last_notice > 20:
            print('Running:', len(report.get('scroll', [])), 'scroll runs,',
                  len(report.get('memory', [])), 'image cycles', flush=True)
            last_notice = time.monotonic()
        time.sleep(.15 if timeout <= 20 else 2)
    raise TimeoutError('Performance probe did not finish')


try:
    adb('install', '-r', args.profile)
    # This exact directory is owned exclusively by this probe.
    adb('shell', 'run-as', app, 'rm', '-rf', root)
    launch()
    for attempt in range(100):
        if file('seeded'):
            break
        time.sleep(.1)
    else:
        raise TimeoutError('Seed did not finish')
    cold = []
    for run in range(0 if args.images_only or args.suite_only or args.scroll_only else 3):
        adb('shell', 'am', 'force-stop', app)
        adb('shell', 'run-as', app, 'rm', '-f', f'{root}/report.json')
        start = time.monotonic()
        activity = adb('shell', 'am', 'start', '-W', '-n', f'{app}/.MainActivity').stdout
        result = poll_report(20)
        result['hostLaunchToObservedReadyMsUpperBound'] = round((time.monotonic()-start)*1000)
        result['activityStart'] = activity
        cold.append(result)
        print('Cold', run + 1, result, flush=True)
    (out/'cold.json').write_text(json.dumps(cold, indent=2))
    adb('shell', 'am', 'force-stop', app)
    adb('shell', 'run-as', app, 'rm', '-f', f'{root}/report.json')
    adb('shell', 'run-as', app, 'touch', f'{root}/run_suite')
    if args.images_only:
        adb('shell', 'run-as', app, 'touch', f'{root}/images_only')
    if args.scroll_only:
        adb('shell', 'run-as', app, 'touch', f'{root}/scroll_only')
    launch()
    result = poll_report(300)
    (out/'report.json').write_text(json.dumps(result, indent=2))
    trace = file('timeline.json')
    if trace:
        (out/'timeline.json').write_text(trace)
    (out/'meminfo.txt').write_text(adb('shell', 'dumpsys', 'meminfo', app).stdout)
    print('Suite', result.get('status'), result.get('error', ''), flush=True)
    if result.get('status') != 'PASS':
        raise RuntimeError(result.get('error', 'probe failed'))
finally:
    # Preserve the partial report even if the run times out.
    raw = file('report.json')
    if raw:
        (out/'last-report.json').write_text(raw)
    adb('shell', 'am', 'force-stop', app, check=False)
    adb('shell', 'run-as', app, 'rm', '-rf', root, check=False)
    adb('install', '-r', args.restore)
    launch()
    print('Production APK restored', flush=True)
