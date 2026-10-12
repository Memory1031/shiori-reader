import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:shiori/features/reader/epub_page_inspection.dart';
import 'package:shiori/shared/epub_link_address.dart';
import 'loss_model.dart';
import 'plan.dart';
import 'report.dart';
import 'replay.dart' show systemAbsolute;

/// A signal remains effective between workers for the whole verification run.
final class ProbeCancellation {
  ProbeCancellation({Stream<ProcessSignal>? signals}) {
    try {
      _signal = (signals ?? ProcessSignal.sigint.watch()).listen(
        (_) => cancel(),
      );
    } on SignalException {
      // Unsupported signals cannot turn incomplete evidence into a pass.
    }
  }
  final _changes = StreamController<void>.broadcast(sync: true);
  StreamSubscription<ProcessSignal>? _signal;
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  Stream<void> get changes => _changes.stream;
  void cancel() {
    if (isCancelled) return;
    _cancelled = true;
    _changes.add(null);
  }

  Future<void> close() async {
    await _signal?.cancel();
    await _changes.close();
  }
}

Future<void> stopOwnedProcess(Process process) async {
  // Only the process started by this command and its own descendants. Never
  // terminate a user's existing browser or another Flutter invocation.
  if (Platform.isWindows) {
    await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
  } else {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }
  await process.exitCode;
}

String? installedChromium() {
  final paths = Platform.isWindows
      ? [
          p.join(
            Platform.environment['PROGRAMFILES(X86)'] ??
                r'C:\Program Files (x86)',
            'Microsoft/Edge/Application/msedge.exe',
          ),
          p.join(
            Platform.environment['PROGRAMFILES'] ?? r'C:\Program Files',
            'Google/Chrome/Application/chrome.exe',
          ),
        ]
      : [
          '/usr/bin/chromium',
          '/usr/bin/chromium-browser',
          '/usr/bin/google-chrome',
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        ];
  return paths.where((path) => File(path).existsSync()).firstOrNull;
}

class _Cdp {
  _Cdp(this.socket) {
    subscription = socket.listen((message) {
      final value = jsonDecode(message as String) as Json;
      if (value['id'] is int) pending.remove(value['id'])?.complete(value);
      if (value['method'] == 'Fetch.requestPaused') {
        final params = value['params'] as Json;
        unawaited(
          call('Fetch.failRequest', {
            'requestId': params['requestId'],
            'errorReason': 'BlockedByClient',
          }),
        );
      }
    });
  }
  final WebSocket socket;
  late final StreamSubscription<dynamic> subscription;
  final pending = <int, Completer<Json>>{};
  var sequence = 0;
  Future<Json> call(String method, [Json params = const {}]) async {
    final id = ++sequence, completion = Completer<Json>();
    pending[id] = completion;
    socket.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    final value = await completion.future.timeout(const Duration(seconds: 10));
    if (value.containsKey('error')) {
      throw const FormatException('Browser protocol rejected measurement');
    }
    return value['result'] as Json? ?? {};
  }

  Future<dynamic> evaluate(String expression) async {
    final result = await call('Runtime.evaluate', {
      'expression': expression,
      'awaitPromise': true,
      'returnByValue': true,
    });
    if (result['exceptionDetails'] != null) {
      throw const FormatException('Browser host measurement failed');
    }
    return (result['result'] as Json)['value'];
  }

  Future<void> close() async {
    await subscription.cancel();
    await socket.close();
  }
}

/// Removes all original text, font names, addresses and bytes before evidence
/// publication. Geometry is retained with explicit viewport and scroll scope.
Json sanitizeBrowserMeasurement(Json raw) {
  final texts = objectList(raw, 'text', max: 128),
      images = objectList(raw, 'images', max: 128),
      links = objectList(raw, 'links', max: 128);
  final safeTexts = <Json>[];
  var clipped = 0,
      observedClipped = 0,
      unknownClipping = 0,
      overlaps = 0,
      lowContrast = 0,
      unknownBackground = 0;
  final width = raw['clientWidth'] as num, height = raw['clientHeight'] as num;
  final dx = (raw['displacement'] as List)[0] as num,
      dy = (raw['displacement'] as List)[1] as num;
  List<double>? color(String? value) {
    final match = RegExp(
      r'^rgb\((\d+),\s*(\d+),\s*(\d+)\)$',
    ).firstMatch(value ?? '');
    if (match == null) return null;
    return [
      for (var i = 1; i <= 3; i++) int.parse(match[i]!).clamp(0, 255) / 255,
    ];
  }

  double luminance(List<double> c) {
    double linear(double n) =>
        n <= .04045 ? n / 12.92 : _pow((n + .055) / 1.055, 2.4);
    return .2126 * linear(c[0]) + .7152 * linear(c[1]) + .0722 * linear(c[2]);
  }

  final rectangles = <Json>[];
  for (final text in texts) {
    final source = text['text'] as String;
    final boxes = (text['boxes'] as List).cast<Json>();
    final ancestors = objectList(text, 'ancestorClips', max: 128);
    final uncertainClip =
        text['visibilityUnknown'] != false ||
        !text.containsKey('ancestorClips') ||
        text['rangesComplete'] == false ||
        ancestors.any((a) => (a['scrollLeft'] as num) < 0) ||
        // Moving descendants through nested clipping scopes needs more than
        // the current axis-aligned rectangles; do not invent reachability.
        ancestors.length > 1 &&
            ancestors.any(
              (a) =>
                  {'auto', 'scroll'}.contains(a['overflowX']) &&
                      (a['maxScrollLeft'] as num) > 0 ||
                  {'auto', 'scroll'}.contains(a['overflowY']) &&
                      (a['maxScrollTop'] as num) > 0,
            );
    if (uncertainClip) unknownClipping++;
    var visibleLeft = 0.0,
        visibleTop = 0.0,
        visibleRight = width.toDouble(),
        visibleBottom = height.toDouble();
    var reachableLeft = 0.0,
        reachableTop = 0.0,
        reachableRight = (width + dx).toDouble(),
        reachableBottom = (height + dy).toDouble();
    for (final ancestor in ancestors) {
      final r = ancestor['rect'] as Json;
      for (final axis in ['X', 'Y']) {
        final overflow = ancestor['overflow$axis'];
        if (overflow == 'visible') continue;
        final horizontal = axis == 'X';
        final lo = (r[horizontal ? 'left' : 'top'] as num).toDouble();
        final hi = (r[horizontal ? 'right' : 'bottom'] as num).toDouble();
        final scroll =
            (ancestor[horizontal ? 'scrollLeft' : 'scrollTop'] as num)
                .toDouble();
        final maximum =
            (ancestor[horizontal ? 'maxScrollLeft' : 'maxScrollTop'] as num)
                .toDouble();
        // Scrollbar styling does not change wheel/touch scrollability. First
        // intersect the viewport with the container, then translate the whole
        // intersection into the text's current coordinates over its scroll
        // extent, including positions above/left of the current viewport.
        final scrollable = {'auto', 'scroll'}.contains(overflow);
        if (horizontal) {
          visibleLeft = math.max(visibleLeft, lo);
          visibleRight = math.min(visibleRight, hi);
          reachableLeft = math.max(reachableLeft, lo);
          reachableRight = math.min(reachableRight, hi);
          if (scrollable && reachableLeft < reachableRight) {
            reachableLeft -= scroll;
            reachableRight += maximum - scroll;
          }
        } else {
          visibleTop = math.max(visibleTop, lo);
          visibleBottom = math.min(visibleBottom, hi);
          reachableTop = math.max(reachableTop, lo);
          reachableBottom = math.min(reachableBottom, hi);
          if (scrollable && reachableTop < reachableBottom) {
            reachableTop -= scroll;
            reachableBottom += maximum - scroll;
          }
        }
      }
    }
    final visibleBoxes = <Json>[];
    final fg = color(text['color'] as String?),
        bg = color(text['background'] as String?);
    double? contrast;
    if (fg != null && bg != null) {
      final a = luminance(fg), b = luminance(bg);
      contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
      if (contrast < 1.5) lowContrast++;
    } else {
      unknownBackground++;
    }
    for (final rect in boxes) {
      final left = (rect['left'] as num).toDouble(),
          top = (rect['top'] as num).toDouble(),
          right = (rect['right'] as num).toDouble(),
          bottom = (rect['bottom'] as num).toDouble();
      if (right <= left || bottom <= top) {
        if (!uncertainClip) clipped++;
        continue;
      }
      if (!uncertainClip &&
          (left < reachableLeft - 1 ||
              top < reachableTop - 1 ||
              right > reachableRight + 1 ||
              bottom > reachableBottom + 1)) {
        clipped++;
      }
      if (!uncertainClip &&
          (left < visibleLeft - 1 ||
              top < visibleTop - 1 ||
              right > visibleRight + 1 ||
              bottom > visibleBottom + 1)) {
        observedClipped++;
      }
      if (uncertainClip) continue;
      final shown = <String, dynamic>{
        'left': math.max(left, visibleLeft),
        'top': math.max(top, visibleTop),
        'right': math.min(right, visibleRight),
        'bottom': math.min(bottom, visibleBottom),
      };
      if ((shown['right'] as num) <= (shown['left'] as num) ||
          (shown['bottom'] as num) <= (shown['top'] as num)) {
        continue;
      }
      visibleBoxes.add(shown);
      for (final other in rectangles.take(256)) {
        final intersectWidth =
            _min(shown['right'] as double, (other['right'] as num).toDouble()) -
            _max(shown['left'] as double, (other['left'] as num).toDouble());
        final intersectHeight =
            _min(
              shown['bottom'] as double,
              (other['bottom'] as num).toDouble(),
            ) -
            _max(shown['top'] as double, (other['top'] as num).toDouble());
        if (intersectWidth > 3 &&
            intersectHeight > 3 &&
            intersectWidth * intersectHeight >
                (right - left) * (bottom - top) * .3) {
          overlaps++;
        }
      }
      if (rectangles.length < 256) rectangles.add(shown);
    }
    safeTexts.add({
      'domPath': text['domPath'],
      'textHash': digest(source),
      'characters': source.runes.length,
      'sourceUnit': 'unicode_code_point',
      'browserRangeUnit': 'utf16',
      'boxes': boxes,
      'visibleBoxes': visibleBoxes,
      'visibility': uncertainClip
          ? 'unknown'
          : visibleBoxes.isEmpty
          ? 'clipped'
          : 'visible',
      'ancestorClips': [
        for (final a in ancestors)
          {
            for (final field in [
              'domPath',
              'rect',
              'overflowX',
              'overflowY',
              'scrollLeft',
              'scrollTop',
              'maxScrollLeft',
              'maxScrollTop',
              'scrollbarsHidden',
            ])
              field: a[field],
          },
      ],
      'color': text['color'],
      'background': text['background'],
      'contrast': contrast,
      'fontFamilyHash': digest(text['fontFamily'] as String),
      'fontSize': text['fontSize'],
      'lineHeight': text['lineHeight'],
      'clip': text['clip'],
      'opacity': text['opacity'],
    });
  }
  return {
    for (final field in [
      'clientWidth',
      'scrollWidth',
      'clientHeight',
      'scrollHeight',
      'displacement',
      'fontsReady',
      'truncated',
      'rootOverflowX',
      'rootOverflowY',
      'scrollbarsHidden',
    ])
      field: raw[field],
    'text': safeTexts,
    'images': images,
    'links': [
      for (final link in links)
        {
          'domPath': link['domPath'],
          'rect': link['rect'],
          'presentationId': epubLinkId(link['address'] as String?),
        },
    ],
    'unreachableClippedRanges': clipped,
    'observedClippedRanges': observedClipped,
    'unknownClippingRanges': unknownClipping,
    'clippingSourceIntent': 'unverified',
    'geometryFailureCauses': [
      if (clipped > 0) 'unreachable_clipping',
      if (lowContrast > 0) 'low_contrast',
      if (images.any((i) => i['complete'] == true && i['naturalWidth'] == 0))
        'image_decode',
    ],
    'overlappingTextRanges': overlaps,
    'lowContrastRanges': lowContrast,
    'unknownBackgroundRanges': unknownBackground,
    'overflowIsNotClipping': true,
    'fontGlyphAttribution': 'unknown',
  };
}

CheckStatus browserGeometryStatus(Json measurements) =>
    (measurements['geometryFailureCauses'] as List).isNotEmpty
    ? CheckStatus.fail
    : measurements['truncated'] == true ||
          (measurements['overlappingTextRanges'] as int) > 0 ||
          (measurements['unknownBackgroundRanges'] as int) > 0 ||
          (measurements['unknownClippingRanges'] as int) > 0
    ? CheckStatus.unknown
    : CheckStatus.pass;

Future<Json> runBrowserProbe(
  String html,
  Directory privateRoot,
  VerificationTarget target,
  ProbeConfiguration configuration, {
  String? screenshot,
  ProbeCancellation? cancellation,
  String? testOnlyBeforeInspection,
  void Function()? testOnlyOnStarted,
  String? testOnlyExecutable,
}) async {
  if (cancellation?.isCancelled == true) {
    return {
      'complete': false,
      'observedPath': 'not_run',
      'reason': 'interrupted',
      'layers': <String, dynamic>{},
      'assertions': <String, dynamic>{},
    };
  }
  final executable = testOnlyExecutable ?? installedChromium();
  if (executable == null) {
    return {
      'complete': false,
      'reason': 'capability_unavailable',
      'observedPath': 'not_run',
      'layers': {for (final e in EvidenceLayer.values) wireName(e): 'not_run'},
      'assertions': {},
    };
  }
  if (utf8.encode(html).length > 16 * 1024 * 1024) {
    throw const FormatException('Browser document budget');
  }
  final profile = await Directory(
    p.join(privateRoot.path, 'browser-profile'),
  ).create();
  final process = await Process.start(executable, [
    '--headless=new',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-extensions',
    '--disable-features=Translate,OptimizationHints',
    '--remote-debugging-address=127.0.0.1',
    '--remote-debugging-port=0',
    '--user-data-dir=${profile.path}',
    'about:blank',
  ]);
  final out = process.stdout.drain<void>(), err = process.stderr.drain<void>();
  int? exitCode;
  unawaited(process.exitCode.then((code) => exitCode = code));
  _Cdp? client;
  final runCancellation = cancellation ?? ProbeCancellation();
  Future<void>? stopping;
  void stop() {
    stopping ??= stopOwnedProcess(process);
  }

  final cancellationSubscription = runCancellation.changes.listen(
    (_) => stop(),
  );
  if (runCancellation.isCancelled) stop();
  final timeout = Timer(Duration(seconds: target.timeoutSeconds), stop);
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    testOnlyOnStarted?.call();
    final portFile = File(p.join(profile.path, 'DevToolsActivePort'));
    for (
      var i = 0;
      i < 100 &&
          !await portFile.exists() &&
          !runCancellation.isCancelled &&
          exitCode == null;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!await portFile.exists()) {
      if (exitCode != null) {
        throw FormatException(
          'Browser exited before endpoint (code $exitCode)',
        );
      }
      throw const FormatException('Browser endpoint unavailable');
    }
    final port = int.parse((await portFile.readAsLines()).first);
    final request = await http.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/list'),
    );
    final response = await request.close();
    final list = jsonDecode(await utf8.decodeStream(response)) as List;
    final tab = list.cast<Json>().firstWhere((row) => row['type'] == 'page');
    client = _Cdp(
      await WebSocket.connect(tab['webSocketDebuggerUrl'] as String),
    );
    await client.call('Page.enable');
    await client.call('Fetch.enable', {
      'patterns': [
        {'urlPattern': 'http://*'},
        {'urlPattern': 'https://*'},
      ],
    });
    await client.call('Emulation.setDeviceMetricsOverride', {
      'width': configuration.width,
      'height': configuration.height,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await client.call('Page.navigate', {
      'url': 'data:text/html;base64,${base64Encode(utf8.encode(html))}',
    });
    for (var i = 0; i < 100; i++) {
      if (await client.evaluate('document.readyState') == 'complete') break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (testOnlyBeforeInspection != null) {
      await client.evaluate(testOnlyBeforeInspection);
    }
    final before = await client.evaluate(epubPageInspectionScript) as Json;
    if (runCancellation.isCancelled) {
      throw const FormatException('Probe interrupted');
    }
    final measurements = sanitizeBrowserMeasurement(before);
    final scope = target.candidate.location.domPath;
    measurements['targetVisible'] =
        scope == 'document' ||
        (measurements['text'] as List).cast<Json>().any(
          (t) =>
              ((t['domPath'] as String) == scope ||
                  (t['domPath'] as String).startsWith('$scope/')) &&
              (t['visibleBoxes'] as List).isNotEmpty,
        );
    var clicked = false;
    await client.evaluate(
      r'''window.__shioriProbeClicks=[];document.addEventListener('click',e=>{
      const a=e.target.closest('a');if(a){e.preventDefault();window.__shioriProbeClicks.push(a.getAttribute('href'));}},true);''',
    );
    final links = (before['links'] as List).cast<Json>();
    final link = links
        .where((l) => epubLinkId(l['address'] as String?) != null)
        .firstOrNull;
    if (link != null) {
      final r = link['rect'] as Json;
      final x = ((r['left'] as num) + (r['right'] as num)) / 2,
          y = ((r['top'] as num) + (r['bottom'] as num)) / 2;
      if (x >= 0 &&
          x < configuration.width &&
          y >= 0 &&
          y < configuration.height) {
        await client.call('Input.dispatchMouseEvent', {
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'clickCount': 1,
        });
        await client.call('Input.dispatchMouseEvent', {
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'left',
          'clickCount': 1,
        });
        final clicks =
            await client.evaluate('window.__shioriProbeClicks') as List;
        clicked =
            clicks.length == 1 &&
            epubLinkId(clicks.first as String?) ==
                epubLinkId(link['address'] as String?);
        measurements['browserInput'] = {
          'activations': clicks.length,
          'declaredId': epubLinkId(link['address'] as String?),
          'matched': clicked,
        };
      }
    }
    if (screenshot != null && target.maxScreenshots > 0) {
      final capture = await client.call('Page.captureScreenshot', {
        'format': 'png',
      });
      final png = base64Decode(capture['data'] as String);
      if (png.length > target.maxEvidenceBytes) {
        throw const FormatException('Screenshot budget');
      }
      await File(screenshot).writeAsBytes(png, flush: true);
    }
    final status = browserGeometryStatus(measurements);
    final unknown =
        status == CheckStatus.unknown || measurements['targetVisible'] != true;
    return {
      'complete': !unknown,
      'observedPath': 'presentation',
      'reason': unknown ? 'partial_or_ambiguous_geometry' : 'executed',
      'providerDetail': 'browser_Chromium',
      'layers': {
        for (final layer in EvidenceLayer.values)
          wireName(layer): layer == EvidenceLayer.browserGeometry
              ? status == CheckStatus.fail
                    ? 'fail'
                    : unknown
                    ? 'unknown'
                    : 'pass'
              : layer == EvidenceLayer.controlRouting && clicked
              ? 'pass'
              : 'not_run',
      },
      'assertions': measurements,
      'environmentDetail': await client.call('Browser.getVersion'),
    };
  } catch (_) {
    if (!runCancellation.isCancelled) rethrow;
    return {
      'complete': false,
      'observedPath': 'not_run',
      'reason': 'interrupted',
      'layers': <String, dynamic>{},
      'assertions': <String, dynamic>{},
    };
  } finally {
    timeout.cancel();
    await cancellationSubscription.cancel();
    http.close(force: true);
    if (client != null) {
      if (!runCancellation.isCancelled && stopping == null) {
        try {
          await client.call('Browser.close');
        } catch (_) {
          /* Process cleanup below. */
        }
      }
      await client.close();
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      stop();
    }
    if (stopping != null) await stopping;
    await Future.wait([out, err]);
    final canonical = await profile.resolveSymbolicLinks();
    if (p.equals(systemAbsolute(profile.path), p.normalize(canonical)) &&
        p.isWithin(systemAbsolute(privateRoot.path), canonical)) {
      await profile.delete(recursive: true);
    }
    if (cancellation == null) await runCancellation.close();
  }
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
double _pow(double n, double exponent) => math.pow(n, exponent).toDouble();
