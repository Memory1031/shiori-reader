import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/reader_theme.dart';

import '../../../tool/epub_audit/browser_probe.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../tool/epub_loss_browser_test.dart'
    show browserTarget, chromiumTestSkip;

String presentation(String body) {
  final files = epubFiles();
  files['OPS/text/a.xhtml'] = utf8.encode(body);
  final parser = EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('f' * 64),
    'settings-fixture.epub',
    includePresentations: true,
  );
  parser.parse();
  return parser.presentations.values.single;
}

void main() {
  test(
    'Chromium preserves authored CSS geometry across reader papers',
    () async {
      final source = presentation('''<html><head><style>
@layer publisher{.layered{max-width:120px;}}
body{font-size:18px;margin:24px;background:#ffeedd;}
#frame{position:relative;height:1600px;}
#explicit{font-family:monospace;font-size:26px;line-height:39px;
color:#123456;background:#f1e2d3;margin:11px 13px;position:absolute;
top:20px;left:10px;transform:translate(7px,9px);width:260px;}
#vertical{position:absolute;top:180px;left:300px;width:28px;height:100px;
writing-mode:vertical-rl;font-size:16px;line-height:24px;}
#layered{position:absolute;top:330px;left:10px;width:100%;}
#inherited{position:absolute;top:420px;left:10px;}
img{position:absolute;top:480px;left:10px;width:600px;}
a{position:absolute;top:550px;left:10px;color:#123456;}
</style><script>window.authorScriptRan=true;</script></head><body>
<div id="frame"><p id="explicit" onclick="window.authorScriptRan=true">Authored text</p>
<p id="vertical">Vertical text</p><p id="layered" class="layered">Layered width</p>
<p id="inherited">Inherited ink</p>
<img src="../images/星 空.png" alt="embedded image"/>
<a href="b.xhtml#b">Chapter link</a></div></body></html>''');
      expect(source, isNot(contains('<script')));
      expect(source, isNot(contains('onclick')));
      final root = await Directory.systemTemp.createTemp(
        'shiori-settings-css-',
      );
      try {
        final target = browserTarget();
        final themeCases = [
          ('paper', ReaderSettings(themeMode: ReaderThemeMode.light)),
          (
            'warm',
            ReaderSettings(
              themeMode: ReaderThemeMode.light,
              paper: ReaderPaper.warm,
            ),
          ),
          ('night', ReaderSettings(themeMode: ReaderThemeMode.dark)),
        ];
        List<dynamic>? authoredGeometry;
        for (final (name, settings) in themeCases) {
          final theme = readerTheme(settings, Brightness.light);
          String rgb(Color c) =>
              'rgb(${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()})';
          final directory = await Directory('${root.path}/$name').create();
          final result = await runBrowserProbe(
            epubLayoutDocument(
              source,
              theme.scaffoldBackgroundColor,
              theme.colorScheme.onSurface,
              theme.brightness,
              false,
            ),
            directory,
            target,
            target.configurations.single,
            screenshot: '${directory.path}/page.png',
            // Fixed test assertions run through CDP; EPUB scripts remain absent
            // and forbidden by the unchanged production parser and host CSPs.
            testOnlyBeforeInspection:
                '''(()=>{
const check=(ok)=>{if(!ok)throw Error('Authored settings boundary changed');};
const css=id=>getComputedStyle(document.getElementById(id));
const body=getComputedStyle(document.body), explicit=css('explicit');
check(!window.authorScriptRan);
check(body.backgroundColor===${jsonEncode(rgb(theme.scaffoldBackgroundColor))});
check(body.color===${jsonEncode(rgb(theme.colorScheme.onSurface))});
check(body.fontSize==='20px' && body.paddingLeft==='8px' && body.marginLeft==='0px');
check(explicit.color==='rgb(18, 52, 86)' && explicit.backgroundColor==='rgb(241, 226, 211)');
check(explicit.fontFamily==='monospace' && explicit.fontSize==='26px' && explicit.lineHeight==='39px');
check(explicit.marginLeft==='13px' && explicit.position==='absolute');
check(explicit.transform==='matrix(1, 0, 0, 1, 7, 9)');
check(css('vertical').writingMode==='vertical-rl');
check(css('layered').maxWidth==='120px');
check(css('inherited').color===body.color);
const image=document.querySelector('img');
check(image.complete && image.naturalWidth===1 && image.getBoundingClientRect().width===384);
check(document.querySelector('a').getAttribute('href').startsWith('https://shiori.invalid/'));
window.scrollTo(0,650);check(window.scrollY===650);window.scrollTo(0,0);
})()''',
          );
          if (installedChromium() == null) {
            expect(result['reason'], 'capability_unavailable');
            return;
          }
          expect(result['assertions']['fontsReady'], true);
          expect(result['assertions']['browserInput']['matched'], true);
          final text = result['assertions']['text'] as List;
          final geometry = [
            for (final row in text)
              [
                row['domPath'],
                row['boxes'],
                row['fontSize'],
                row['lineHeight'],
              ],
          ];
          authoredGeometry ??= geometry;
          expect(geometry, authoredGeometry, reason: name);
          final evidence =
              Platform.environment['SHIORI_PRESENTATION_SETTINGS_EVIDENCE'];
          if (evidence != null) {
            await Directory(evidence).create(recursive: true);
            await File(
              '$evidence/$name.json',
            ).writeAsString(jsonEncode(result));
            await File(
              '${directory.path}/page.png',
            ).copy('$evidence/$name.png');
          }
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: chromiumTestSkip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Chromium keeps explicit SVG fill while theming unfilled text',
    () async {
      final source = presentation('''<html><body>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 700">
<image x="0" y="0" width="400" height="700" href="../images/星 空.png"/>
<text x="20" y="50" font-size="26">Inherited SVG ink</text>
<text x="20" y="100" font-size="26" fill="#125678">Authored SVG ink</text>
</svg></body></html>''');
      final root = await Directory.systemTemp.createTemp(
        'shiori-settings-svg-',
      );
      try {
        final target = browserTarget();
        for (final mode in [ReaderThemeMode.light, ReaderThemeMode.dark]) {
          final theme = readerTheme(
            ReaderSettings(themeMode: mode),
            Brightness.light,
          );
          final ink = mode == ReaderThemeMode.light
              ? 'rgb(0, 0, 0)'
              : 'rgb(${(theme.colorScheme.onSurface.r * 255).round()}, ${(theme.colorScheme.onSurface.g * 255).round()}, ${(theme.colorScheme.onSurface.b * 255).round()})';
          final directory = await Directory(
            '${root.path}/${mode.name}',
          ).create();
          final result = await runBrowserProbe(
            epubLayoutDocument(
              source,
              theme.scaffoldBackgroundColor,
              theme.colorScheme.onSurface,
              theme.brightness,
              false,
            ),
            directory,
            target,
            target.configurations.single,
            testOnlyBeforeInspection:
                '''(()=>{
const text=document.querySelectorAll('svg text');
if(text.length!==2 || getComputedStyle(text[0]).fill!==${jsonEncode(ink)} ||
getComputedStyle(text[1]).fill!=='rgb(18, 86, 120)')throw Error('SVG fill boundary changed');
})()''',
          );
          if (installedChromium() == null) {
            expect(result['reason'], 'capability_unavailable');
            return;
          }
          expect(result['assertions']['fontsReady'], true);
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: chromiumTestSkip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
