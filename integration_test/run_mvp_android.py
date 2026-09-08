"""Drive real Android UI against the synthetic HTTP MVP entry, then restore APK."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

p=argparse.ArgumentParser()
for name in ('adb','serial','profile','restore','output'):
    p.add_argument('--'+name,required=True)
a=p.parse_args()
out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
app='dev.shiori.reader';root='files/test004'
report={}


def adb(*args,check=True,binary=False):
    return subprocess.run([a.adb,'-s',a.serial,*args],check=check,capture_output=True,text=not binary,timeout=60)


def status():
    r=adb('shell','run-as',app,'cat',root+'/status.json',check=False)
    try:return json.loads(r.stdout) if r.returncode==0 else {}
    except json.JSONDecodeError:return {}


def wait(predicate,label,timeout=15):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        state=status()
        if state.get('errors'):raise AssertionError(state['errors'])
        if predicate(state):return state
        time.sleep(.3)
    raise TimeoutError(label+': '+str(status()))


def nodes():
    adb('shell','uiautomator','dump','/sdcard/test004-ui.xml')
    xml=adb('shell','cat','/sdcard/test004-ui.xml').stdout
    return list(ET.fromstring(xml).iter('node'))


def click(label,contains=False):
    for attempt in range(4):
        matches=[n for n in nodes() if any((label in n.get(k,'') if contains else label==n.get(k,'')) for k in ('text','content-desc'))]
        if matches:
            n=matches[0]
            x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
            adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
            time.sleep(.6)
            return
        time.sleep(.5)
    raise AssertionError('UI label missing: '+label)


def launch():
    adb('shell','am','start','-n',app+'/.MainActivity')


def shot(name):
    (out/name).write_bytes(adb('exec-out','screencap','-p',binary=True).stdout)


try:
    adb('install','-r',a.profile)
    adb('shell','am','force-stop',app)
    adb('shell','run-as',app,'rm','-rf',root)
    launch()
    initial=wait(lambda s:'calls' in s,'home')
    assert initial['calls']==0 and initial['shelfCount']==0
    click('Search')
    edit=next(n for n in nodes() if n.get('class')=='android.widget.EditText')
    x1,y1,x2,y2=map(int,re.findall(r'\d+',edit.get('bounds')))
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
    adb('shell','input','text','MVP')
    time.sleep(.7)
    assert status()['calls']==0,'Typing unexpectedly requested Source'
    adb('shell','input','keyevent','66')
    wait(lambda s:'search' in s.get('stages',[]),'search')
    time.sleep(.7)
    click('MVP Sample',contains=True)
    click('Add to bookshelf')
    wait(lambda s:s.get('shelfCount')==1,'shelf add')
    click('Start reading')
    warm=wait(lambda s:s.get('reading') and any(not x.startswith('cover:') for x in s.get('decodedMedia',[])) and s.get('saved') is not None,'reader and image')
    shot('warm-reader.png')
    for _ in range(3):
        adb('shell','input','swipe','500','1800','500','700','600')
    warm=wait(lambda s:(s.get('saved') or {}).get('index',0)>1,'progress commit')
    time.sleep(.6)
    warm=status()
    report['warm']=warm
    (out/'warm.json').write_text(json.dumps(warm,indent=2))
    # Deliberately kill while reading after a confirmed real SQLite commit.
    adb('shell','am','force-stop',app)
    adb('shell','run-as',app,'touch',root+'/offline')
    adb('shell','run-as',app,'rm','-f',root+'/status.json')
    launch()
    cold=wait(lambda s:s.get('offline') and s.get('shelfCount')==1 and 'cover:v1:1' in s.get('decodedMedia',[]),'offline bookshelf and cover')
    assert cold['calls']==0,'Offline home requested Source'
    assert cold['initialSaved']==warm['saved'],'Cold progress differs from committed position'
    shot('cold-home.png')
    click('MVP Sample',contains=True)
    restored=wait(lambda s:s.get('reading') and s.get('current') is not None,'offline reader')
    assert restored['calls']==0,'Continue reading requested Source'
    assert restored['current']['blockKey']==warm['saved']['blockKey']
    assert abs(restored['current']['fraction']-warm['saved']['fraction'])<.02
    shot('cold-reader.png')
    for _ in range(4):
        adb('shell','input','swipe','500','700','500','1800','600')
    illustration=wait(lambda s:any(not x.startswith('cover:') for x in s.get('decodedMedia',[])), 'offline chapter illustration')
    assert illustration['calls']==0
    shot('cold-illustration.png')
    report.update(cold=cold,restored=restored,illustration=illustration,status='PASS')
    print('MVP PASS: search, shelf, reader/image, SQLite commit, Android force-stop, offline home/continue; zero cold requests',flush=True)
except Exception as error:
    report.update(status='FAIL',error=str(error),last=status())
    try:
        report['ui']=[{'text':n.get('text'),'description':n.get('content-desc')} for n in nodes() if n.get('text') or n.get('content-desc')]
        shot('failure.png')
    except Exception:pass
    raise
finally:
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    adb('shell','am','force-stop',app,check=False)
    adb('shell','run-as',app,'rm','-rf',root,check=False)
    adb('shell','rm','-f','/sdcard/test004-ui.xml',check=False)
    adb('install','-r',a.restore)
    launch()
    print('Production APK restored',flush=True)
