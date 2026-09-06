import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:image/image.dart' as image;
import 'package:shiori_source_probe/source_probe.dart';
import 'package:test/test.dart';

final fixtures = Directory('../../test/fixtures/lightnovel');
final apiUri = Uri.parse('$site${apiPrefix}bff/apk-search-result-v1');
final mediaUri = Uri.parse(
  'https://api.lightnovel.fun/upload-files/images/250524/abcdef.jpg?m=SECRET_SENTINEL&t=123',
);
final png = File(
  '${fixtures.path}/assets/synthetic-checker.png',
).readAsBytesSync();
final goodIdentity = <String, dynamic>{
  'book_id': bookId,
  'title': bookTitle,
  'author_name': author,
};
final goodChapter = <String, dynamic>{
  'book_id': bookId,
  'volume_id': volumeId,
  'chapter_id': chapterId,
  'locked': 0,
};

Matcher fails(String code) =>
    isA<ProbeFailure>().having((e) => e.code, 'code', code);
WireResponse jsonResponse(Object value) => WireResponse(
  200,
  'application/json',
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': value}))),
);
Json readFixture(String path) =>
    object(jsonDecode(File('${fixtures.path}/$path').readAsStringSync()));

// Deliberately synthetic response bodies; never claim these are captured JSON.
List<WireResponse> chain({Json? chapter}) => [
  jsonResponse({
    'list': [goodIdentity],
    'pagination': {'page': 1},
  }),
  jsonResponse({
    ...goodIdentity,
    'default_volume_id': volumeId,
    'default_chapter_id': chapterId,
  }),
  jsonResponse({
    'list': [
      {'volume_id': volumeId},
    ],
    'pagination': {'page': 1, 'page_count': 1, 'total': 1},
  }),
  jsonResponse({
    'list': [goodChapter],
    'pagination': {'page': 1, 'page_count': 1, 'total': 1},
  }),
  jsonResponse(
    chapter ??
        {
          ...goodChapter,
          'body_snapshot': {
            'body_html':
                '<p>合成正文 SECRET_BODY_SENTINEL</p><p><img src="$mediaUri"></p>',
            'body_text': '合成正文 SECRET_BODY_SENTINEL',
          },
        },
  ),
  WireResponse(200, 'image/png', png),
];

BudgetTransport fakeTransport(List<WireResponse> responses, {int limit = 30}) {
  var i = 0;
  return BudgetTransport(
    live: true,
    limit: limit,
    spacing: Duration.zero,
    exchange: (method, uri, body, maxBytes) async => responses[i++],
  );
}

class DenyHttp extends HttpOverrides {
  int creations = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    creations++;
    throw StateError('offline must not create HttpClient');
  }
}

void main() {
  test(
    'default mode verifies all fixtures without creating an HTTP client',
    () async {
      final override = DenyHttp();
      await HttpOverrides.runWithHttpOverrides(() async {
        final report = await Probe(
          fixtures: fixtures,
          transport: BudgetTransport(live: false),
        ).run();
        expect(report['status'], 'PASS');
        expect(report['httpAttempts'], 0);
        expect(report['stages'], hasLength(5));
      }, override);
      expect(override.creations, 0);
    },
  );

  test('disabled transport rejects before calling exchange', () async {
    var calls = 0;
    final transport = BudgetTransport(
      live: false,
      exchange: (_, _, _, _) async {
        calls++;
        throw StateError('called');
      },
    );
    await expectLater(
      transport.request('POST', apiUri),
      throwsA(fails('live_disabled')),
    );
    expect(calls, 0);
    expect(transport.attempts, isEmpty);
  });

  test('budget accepts only 1..30', () {
    for (final limit in [0, -1, 31, 100]) {
      expect(
        () => BudgetTransport(live: true, limit: limit),
        throwsA(fails('invalid_budget')),
      );
    }
  });

  test('six-stage synthetic chain preserves query only in memory', () async {
    final responses = chain();
    var calls = 0;
    final transport = BudgetTransport(
      live: true,
      spacing: Duration.zero,
      exchange: (method, uri, body, _) async {
        if (calls == 0) expect(body!['q'], '玩乐关系');
        if (calls == 5) {
          expect(method, 'GET');
          expect(uri, mediaUri);
        }
        return responses[calls++];
      },
    );
    final report = await Probe(fixtures: fixtures, transport: transport).run();
    expect(report['status'], 'PASS');
    expect(report['httpAttempts'], 6);
    expect(jsonEncode(report), isNot(contains('SECRET')));
    expect(jsonEncode(report), isNot(contains('abcdef')));
  });

  test(
    'budget exhaustion stops mid-chain and marks remaining stages skipped',
    () async {
      final transport = fakeTransport(chain(), limit: 2);
      final report = await Probe(
        fixtures: fixtures,
        transport: transport,
      ).run();
      expect(report['status'], 'FAIL');
      expect(report['httpAttempts'], 2);
      final stages = report['stages'] as List<Json>;
      expect(stages[7]['failureCode'], 'budget_exhausted');
      expect(stages.last['status'], 'SKIPPED');
    },
  );

  test('same-origin GET redirect consumes a second attempt', () async {
    final transport = fakeTransport([
      WireResponse(302, '', Uint8List(0), location: mediaUri.toString()),
      WireResponse(200, 'image/png', png),
    ]);
    await transport.request('GET', mediaUri);
    expect(transport.attempts.map((a) => a['httpStatus']), [302, 200]);
  });

  test('redirect cannot exceed total attempt budget', () async {
    final transport = fakeTransport([
      WireResponse(302, '', Uint8List(0), location: mediaUri.toString()),
    ], limit: 1);
    await expectLater(
      transport.request('GET', mediaUri),
      throwsA(fails('budget_exhausted')),
    );
    expect(transport.attempts, hasLength(1));
  });

  test('redirect loops stop after three hops', () async {
    final transport = fakeTransport(
      List.generate(
        4,
        (_) =>
            WireResponse(302, '', Uint8List(0), location: mediaUri.toString()),
      ),
    );
    await expectLater(
      transport.request('GET', mediaUri),
      throwsA(fails('redirect_stopped')),
    );
    expect(transport.attempts, hasLength(4));
  });

  test(
    'POST redirects and unknown media origins stop before followup',
    () async {
      for (final method in ['POST', 'GET']) {
        final transport = fakeTransport([
          WireResponse(
            302,
            '',
            Uint8List(0),
            location: 'https://example.com/login?secret=SECRET',
          ),
        ]);
        await expectLater(
          transport.request(method, method == 'POST' ? apiUri : mediaUri),
          throwsA(
            fails(method == 'POST' ? 'redirect_stopped' : 'unsafe_target'),
          ),
        );
        expect(transport.attempts, hasLength(1));
      }
    },
  );

  test('unsafe URLs are rejected with no attempts', () async {
    for (final url in [
      'http://api.lightnovel.fun/upload-files/images/1/ab.jpg',
      'https://api.lightnovel.fun/login',
      'https://a:b@api.lightnovel.fun/upload-files/images/1/ab.jpg',
      'https://api.lightnovel.fun:444/upload-files/images/1/ab.jpg',
      'https://example.com/upload-files/images/1/ab.jpg',
    ]) {
      final transport = fakeTransport([]);
      await expectLater(
        transport.request('GET', Uri.parse(url)),
        throwsA(fails('unsafe_target')),
      );
      expect(transport.attempts, isEmpty);
    }
  });

  test(
    'denials and challenges stop the chain, with no retry or body retention',
    () async {
      for (final status in [401, 403, 429, 503]) {
        final transport = fakeTransport([
          WireResponse(
            status,
            'text/html',
            Uint8List.fromList(utf8.encode('SECRET_CHALLENGE')),
          ),
        ]);
        final report = await Probe(
          fixtures: fixtures,
          transport: transport,
        ).run();
        expect(report['status'], 'FAIL');
        expect(report['httpAttempts'], 1);
        expect(jsonEncode(report), isNot(contains('SECRET')));
        await expectLater(
          transport.request('POST', apiUri),
          throwsA(fails('transport_stopped')),
        );
      }
    },
  );

  test('network failures count once and exceptions are sanitized', () async {
    for (final error in [
      StateError('SECRET_URL'),
      TimeoutException('SECRET_URL'),
    ]) {
      final transport = BudgetTransport(
        live: true,
        spacing: Duration.zero,
        exchange: (_, _, _, _) async => throw error,
      );
      final report = await Probe(
        fixtures: fixtures,
        transport: transport,
      ).run();
      expect(report['httpAttempts'], 1);
      expect(jsonEncode(report), isNot(contains('SECRET')));
      expect(
        (report['stages'] as List<Json>)[5]['failureCode'],
        error is TimeoutException ? 'network_timeout' : 'transport_failed',
      );
    }
  });

  test('simultaneous request is rejected', () async {
    final pending = Completer<WireResponse>();
    final transport = BudgetTransport(
      live: true,
      exchange: (_, _, _, _) => pending.future,
    );
    final first = transport.request('POST', apiUri);
    await expectLater(
      transport.request('POST', apiUri),
      throwsA(fails('concurrent_request')),
    );
    pending.complete(jsonResponse({}));
    await first;
    expect(transport.attempts, hasLength(1));
  });

  test('response byte cap is enforced', () async {
    final transport = fakeTransport([WireResponse(200, 'image/png', png)]);
    await expectLater(
      transport.request('GET', mediaUri, byteLimit: 1),
      throwsA(fails('response_too_large')),
    );
  });

  test('wrong or ambiguous book never becomes a selected result', () {
    expect(
      () => assertBook({...goodIdentity, 'author_name': 'wrong'}),
      throwsA(fails('book_identity_mismatch')),
    );
    expect(
      () => assertBook({...goodIdentity, 'book_id': 1}),
      throwsA(fails('book_identity_mismatch')),
    );
    expect(
      () => selectTarget([goodIdentity, goodIdentity], 'book_id', bookId),
      throwsA(fails('target_missing_or_duplicated')),
    );
    expect(
      () => selectTarget([], 'book_id', bookId),
      throwsA(fails('target_missing_or_duplicated')),
    );
  });

  test(
    'locked, wrong-volume and preview-only chapters stop before media',
    () async {
      for (final chapter in [
        {...goodChapter, 'locked': 1},
        {...goodChapter, 'volume_id': 99},
        {
          ...goodChapter,
          'render_preview': {
            'body_html': '<p>preview</p>',
            'body_text': 'preview',
          },
        },
      ]) {
        final report = await Probe(
          fixtures: fixtures,
          transport: fakeTransport(chain(chapter: chapter)),
        ).run();
        expect(report['status'], 'FAIL');
        expect(report['httpAttempts'], 5);
        expect((report['stages'] as List<Json>).last['status'], 'SKIPPED');
      }
    },
  );

  test('empty text or no illustration cannot pass', () {
    expect(() => inspectBody('<p></p>', ''), throwsA(fails('empty_body')));
    expect(
      () => inspectBody('<p>text</p>', 'text'),
      throwsA(fails('body_image_missing')),
    );
  });

  test(
    'HTML MIME and nonzero business code are not treated as JSON success',
    () async {
      for (final response in [
        WireResponse(200, 'text/html', Uint8List(0)),
        WireResponse(
          200,
          'application/json',
          Uint8List.fromList(
            utf8.encode('{"code":403,"message":"SECRET_REJECTED"}'),
          ),
        ),
      ]) {
        final report = await Probe(
          fixtures: fixtures,
          transport: fakeTransport([response]),
        ).run();
        expect(report['status'], 'FAIL');
        expect(report['httpAttempts'], 1);
        expect(jsonEncode(report), isNot(contains('SECRET')));
      }
    },
  );

  test('decode proof requires image bytes and matching MIME', () {
    expect(decodeIllustration(png, 'image/png')['decoded'], true);
    expect(
      () => decodeIllustration(png, 'image/jpeg'),
      throwsA(fails('image_mime_mismatch')),
    );
    expect(
      () => decodeIllustration(png, 'text/html'),
      throwsA(fails('image_mime_rejected')),
    );
    expect(
      () => decodeIllustration(Uint8List(10), 'image/png'),
      throwsA(isA<ProbeFailure>()),
    );
    final jpeg = image.encodeJpg(image.Image(width: 3, height: 2));
    expect(decodeIllustration(jpeg, 'image/jpeg')['width'], 3);
  });

  test('oversized image metadata is rejected before pixel allocation', () {
    final jpeg = image.encodeJpg(image.Image(width: 3, height: 2));
    var patched = false;
    for (var i = 0; i < jpeg.length - 9; i++) {
      if (jpeg[i] == 0xff && jpeg[i + 1] == 0xc0) {
        // SOF0: marker, length, precision, height, width; no JPEG CRC.
        for (final offset in [5, 6, 7, 8]) {
          jpeg[i + offset] = 0xff;
        }
        patched = true;
        break;
      }
    }
    expect(patched, true);
    expect(
      () => decodeIllustration(jpeg, 'image/jpeg'),
      throwsA(fails('image_dimensions_rejected')),
    );
  });

  test(
    'existing report destination is rejected before live requests',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'bin/source_probe.dart',
        '--live',
        '--report',
        'pubspec.yaml',
      ]);
      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(
        jsonDecode(result.stderr as String),
        containsPair('failureCode', 'report_already_exists'),
      );
    },
  );

  test('synthetic ruby and illustration remain within semantic paragraphs', () {
    final document = html.parseFragment(
      File('${fixtures.path}/synthetic/chapter-shape.html').readAsStringSync(),
    );
    final paragraphs = document.querySelectorAll('p');
    final ruby = paragraphs[2].querySelector('ruby')!;
    expect(ruby.querySelector('rt')!.text, 'test');
    ruby.querySelector('rt')!.remove();
    expect(ruby.text, '测试');
    expect(paragraphs[3].querySelector('img'), isNotNull);
    expect(paragraphs[4].text, isNotEmpty);
  });

  test(
    'captured projected search and catalog remain distinct from synthetic chain',
    () {
      final projected = readFixture('initial-http-observations.json');
      expect(
        projected['evidenceKind'],
        'MANUAL_TRANSCRIPTION_OF_DIRECT_HTTP_OBSERVATIONS',
      );
      final catalog = envelope(
        readFixture('captured/catalog-44117.json')['response'],
      );
      expect(rows(catalog).map((r) => r['chapter_id']), [309555, 309556]);
    },
  );
}
